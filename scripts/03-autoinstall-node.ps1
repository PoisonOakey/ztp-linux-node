<#
.SYNOPSIS
Automates the Ubuntu Server OS installation by injecting cloud-init configuration via a temporary VHD.

.DESCRIPTION
This script performs an unattended installation:
1. Validates Administrative privileges (required for virtual disk creation).
2. Generates a temporary FAT32 Virtual Hard Disk (VHD) labeled "CIDATA".
3. Injects the cloud-init user-data and meta-data configurations.
4. Attaches the configuration disk to the VirtualBox VM.
5. Boots the VM with the GUI attached and clears Subiquity's destructive-disk
   confirmation prompt by injecting a keystroke after a fixed delay.

KNOWN LIMITATION: step 5 is a timing race. The keystroke fires after a fixed
90-second wait with nothing verifying the prompt is actually on screen, so on a
slow disk it types into the void and the install never completes. The GUI is
attached deliberately so the operator can see and correct that. The real fix is
to pass 'autoinstall' on the kernel command line -- which requires rebuilding the
Ubuntu ISO -- and is tracked as deferred work in docs/CHANGELOG.md. The
orchestrator's install wait-loop now bounds the failure at 20 minutes rather
than hanging forever.

.PARAMETER VmName
Name of the Virtual Machine. Defaults to the value in config/node.json.

.PARAMETER LabDir
The directory where the VM disk and ISO are stored. Defaults to the value in config/node.json.
#>
param (
    [string]$VmName,
    [string]$LabDir
)

# config/node.json is the single source of truth for lab/hardware settings;
# explicit arguments still override it for one-off runs.
. (Join-Path $PSScriptRoot "Get-LabConfig.ps1")
$Config = Get-LabConfig -ConfigPath (Join-Path $PSScriptRoot "..\config\node.json")
if (-not $VmName) { $VmName = $Config.vm_name }
if (-not $LabDir) { $LabDir = $Config.lab_dir }

$logDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Start-Transcript -Path (Join-Path $logDir "$scriptName-$timestamp.log") -Append

try {
    $ErrorActionPreference = 'Stop'

    # 0. Validate Administrative Privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "This script requires Administrator privileges to mount virtual disks. Please run PowerShell as Administrator."
        exit 1
    }

    Write-Output "Starting Stage 3: Automated OS Installation for $VmName..."

    # Resolve VBoxManage Path
    $VBoxManage = "VBoxManage.exe"
    if (-not (Get-Command $VBoxManage -ErrorAction SilentlyContinue)) {
        $defaultPath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
        if (Test-Path $defaultPath) {
            $VBoxManage = $defaultPath
        }
        else {
            Write-Error "VBoxManage.exe not found. Is VirtualBox installed?"
            exit 1
        }
    }

    # Ensure VM exists
    $existingVms = & $VBoxManage list vms
    if ($existingVms -notmatch "`"$VmName`"") {
        Write-Error "Virtual Machine '$VmName' does not exist! Please run Stage 2 first."
        exit 1
    }

    # Subiquity ejects the install media at the end of a successful install, so a
    # VM that has already been built has an empty optical drive. Booting it again
    # from here would just start the installed OS and silently do nothing, which
    # looks identical to a hung installer. Fail with the same "run Stage 2 first"
    # guidance the missing-VM check above gives.
    $isoAttached = & $VBoxManage showvminfo $VmName --machinereadable | Select-String '^"IDE Controller-0-0"="(.+\.iso)"$'
    if (-not $isoAttached) {
        Write-Error "No installation ISO is attached to '$VmName' -- its optical drive is empty, so there is nothing to install from. This happens after a successful install, because Subiquity ejects the media. Re-run Stage 2 (or Deploy-Node.ps1, answering 'y' to the wipe prompt) to rebuild the VM with the ISO mounted."
        exit 1
    }

    # If VM is currently running (e.g. from a manual GUI boot), power it off to modify storage
    $runningVms = & $VBoxManage list runningvms
    if ($runningVms -match "`"$VmName`"") {
        Write-Output "-> Powering off the currently running VM to attach configuration..."
        & $VBoxManage controlvm $VmName poweroff
        Start-Sleep -Seconds 3
    }

    $CidataPath = Join-Path $LabDir "cidata.vhd"
    $MountDir = Join-Path $LabDir "cidata_mount"
    $CloudInitDir = Join-Path $PSScriptRoot "cloud-init"

    if (-not (Test-Path (Join-Path $CloudInitDir "user-data"))) {
        Write-Error "cloud-init/user-data file not found! Please ensure it exists."
        exit 1
    }

    if (-not (Test-Path $LabDir)) { New-Item -ItemType Directory -Force -Path $LabDir | Out-Null }

    # ==============================================================================
    # 0b. Prepare SSH key for passwordless authentication
    # ==============================================================================
    # The account password in user-data stays in place as a console/sudo fallback
    # (see TROUBLESHOOTING.md #10), but SSH login itself is key-only. We render the
    # real public key into a throwaway copy under $LabDir -- never back into the
    # tracked scripts/cloud-init/user-data template, so a real key (or a stale
    # diff) never ends up in the repo.
    Write-Output "`n-> Preparing SSH key for passwordless authentication..."

    $sshKeygenPath = if (Test-Path "$env:WINDIR\sysnative\OpenSSH\ssh-keygen.exe") { "$env:WINDIR\sysnative\OpenSSH\ssh-keygen.exe" } else { "$env:WINDIR\System32\OpenSSH\ssh-keygen.exe" }
    $sshKeyDir = Join-Path $HOME ".ssh"
    $publicKeyPath = @("id_ed25519.pub", "id_rsa.pub") | ForEach-Object { Join-Path $sshKeyDir $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $publicKeyPath) {
        Write-Output "   [*] No existing SSH key found in $sshKeyDir. Generating a new ed25519 keypair..."
        if (-not (Test-Path $sshKeyDir)) { New-Item -ItemType Directory -Force -Path $sshKeyDir | Out-Null }
        $newKeyPath = Join-Path $sshKeyDir "id_ed25519"
        & $sshKeygenPath -t ed25519 -f $newKeyPath -N '""' -q
        $publicKeyPath = "$newKeyPath.pub"
    }

    $publicKey = (Get-Content $publicKeyPath -Raw).Trim()
    if (-not $publicKey -or $publicKey -notmatch '^ssh-') {
        Write-Error "Failed to read a valid SSH public key from $publicKeyPath. Aborting before writing user-data to avoid locking SSH out entirely."
        exit 1
    }
    Write-Output "   [*] Using SSH key: $publicKeyPath"

    $RenderedUserData = Join-Path $LabDir "user-data.rendered"
    # SSH public keys are base64 (no '$'), so no regex-replacement escaping is needed for the substitution value.
    (Get-Content (Join-Path $CloudInitDir "user-data") -Raw) -replace 'INSERT_SSH_KEY_HERE', $publicKey | Set-Content -Path $RenderedUserData -NoNewline

    # ==============================================================================
    # 1. Generate the CIDATA Virtual Disk
    # ==============================================================================
    Write-Output "`n-> Generating temporary cloud-init configuration disk..."

    # VirtualBox records cidata.vhd in its media registry (VirtualBox.xml) by UUID.
    # We rebuild the VHD from scratch on every run, so the new file gets a new UUID
    # while the registry still holds the previous one -- which makes the next
    # startvm fail with "UUID ... does not match the value stored in the media
    # registry" and leaves the VM unbootable. Detach it from the VM and drop the
    # stale registry entry before recreating it.
    #
    # We look the entry up by location and close it by UUID rather than by path:
    # closing by path makes VirtualBox open the file and re-check the UUID, which
    # is the very comparison that is already failing.
    #
    # Both steps are conditional rather than fire-and-suppress. VBoxManage errors
    # on an empty slot or an unregistered medium, and in PowerShell 5.1 redirecting
    # a native command's stderr wraps every line in an ErrorRecord, which
    # $ErrorActionPreference = 'Stop' then promotes to a terminating error -- so
    # `2>$null` would abort the script on a first run instead of silencing it.
    Write-Output "   [*] Clearing any previous CIDATA registration from VirtualBox..."

    $cidataSlot = & $VBoxManage showvminfo $VmName --machinereadable | Select-String '^"SATA Controller-1-0"="(.+)"$'
    if ($cidataSlot -and $cidataSlot.Matches[0].Groups[1].Value -ne 'none') {
        & $VBoxManage storageattach $VmName --storagectl "SATA Controller" --port 1 --device 0 --medium none
    }

    $registeredUuid = $null
    $lastUuid = $null
    foreach ($line in (& $VBoxManage list hdds)) {
        if ($line -match '^UUID:\s+(\S+)') { $lastUuid = $Matches[1] }
        elseif ($line -match '^Location:\s+(.+)$' -and $Matches[1].Trim() -eq $CidataPath) {
            $registeredUuid = $lastUuid
            break
        }
    }
    if ($registeredUuid) {
        & $VBoxManage closemedium disk $registeredUuid
    }

    if (Test-Path $CidataPath) {
        # Attempt to detach it just in case a previous run crashed. This is a
        # second layer of defence -- the try/finally below is the first.
        $detachScript = @"
select vdisk file="$CidataPath"
detach vdisk
"@
        $detachScript | diskpart.exe | Out-Null
        Remove-Item -Path $CidataPath -Force -ErrorAction SilentlyContinue
    }

    # We use diskpart to create a dynamically expanding 10MB VHD, format it FAT32, and assign a drive letter.
    # Everything between 'attach vdisk' and 'detach vdisk' is wrapped so a failure
    # in the middle can never leave a mounted VHD holding a live drive letter.
    try {
        $diskpartScript = @"
create vdisk file="$CidataPath" maximum=50 type=expandable
select vdisk file="$CidataPath"
attach vdisk
convert mbr
create partition primary
format fs=fat32 label=CIDATA quick
assign
"@

        Write-Output "   [*] Running diskpart to provision VHD..."
        $diskpartScript | diskpart.exe | Out-Null

        # Find the drive letter assigned by diskpart
        $Volume = $null
        for ($i = 0; $i -lt 5; $i++) {
            $Volume = Get-Volume | Where-Object { $_.FileSystemLabel -eq "CIDATA" }
            if ($Volume -and $Volume.DriveLetter) { break }
            Start-Sleep -Seconds 1
        }

        if (-not $Volume -or -not $Volume.DriveLetter) {
            Write-Error "Failed to find the mounted CIDATA volume. Diskpart may have failed."
            exit 1
        }

        $MountDir = "$($Volume.DriveLetter):\"

        # ==============================================================================
        # 2. Inject Configuration Files
        # ==============================================================================
        Write-Output "-> Injecting user-data and meta-data..."
        Copy-Item -Path $RenderedUserData -Destination (Join-Path $MountDir "user-data") -Force
        Copy-Item -Path (Join-Path $CloudInitDir "meta-data") -Destination $MountDir -Force

        # Small sleep to ensure file locks are released
        Start-Sleep -Seconds 1
    }
    finally {
        # Cleanup must never throw -- a failure here would replace the real
        # exception and hide why the run actually died.
        $ErrorActionPreference = 'Continue'
        Write-Output "-> Safely unmounting configuration disk..."
        $diskpartUnmount = @"
select vdisk file="$CidataPath"
detach vdisk
"@
        $diskpartUnmount | diskpart.exe | Out-Null
        $ErrorActionPreference = 'Stop'
    }

    # ==============================================================================
    # 3. Attach Disk and Boot VM
    # ==============================================================================
    Write-Output "`n-> Attaching configuration disk to VM..."
    # $ErrorActionPreference = 'Stop' does NOT apply to native executables -- a
    # failing VBoxManage call sets $LASTEXITCODE and execution carries on. Without
    # these guards a failed attach or boot fell straight through to the 90-second
    # sleep, typed into a VM that was not running, and printed the success banner
    # below on a run that did nothing at all.
    # We attach it to the SATA controller on port 1 (port 0 is the main OS disk)
    & $VBoxManage storageattach $VmName --storagectl "SATA Controller" --port 1 --device 0 --type hdd --medium $CidataPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to attach the cloud-init disk to '$VmName' (VBoxManage exit $LASTEXITCODE). The VM was not started and no installation was triggered."
    }

    Write-Output "-> Booting VM with GUI for automated installation monitoring..."
    & $VBoxManage startvm $VmName --type gui
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start '$VmName' (VBoxManage exit $LASTEXITCODE). No installation was triggered."
    }

    # See KNOWN LIMITATION in the header. This is a fixed-delay race, not a
    # verified handshake: nothing here confirms Subiquity's confirmation prompt
    # is actually on screen before the keystroke is sent.
    Write-Output "-> Waiting 90 seconds for Ubuntu installer to prompt for confirmation..."
    Start-Sleep -Seconds 90
    Write-Output "-> Injecting 'yes' to bypass Subiquity safety check..."
    & $VBoxManage controlvm $VmName keyboardputstring "yes"
    # Send 'Enter' scancode (Make: 1c, Break: 9c)
    & $VBoxManage controlvm $VmName keyboardputscancode 1c 9c

    Write-Output "`n=================================================="
    Write-Output "Automated installation has been triggered!"
    Write-Output "The VM is running in the background. It will automatically install the OS and power off when complete."
    Write-Output "You can monitor its status by opening the VirtualBox GUI and watching the preview window."
    Write-Output "Once it powers off automatically, you can boot it again and SSH in as 'sysadmin'."
}
finally {
    Stop-Transcript
}
