<#
.SYNOPSIS
Master execution script that runs all stages sequentially to fully bootstrap the node.

.DESCRIPTION
This script acts as the orchestrator for the entire pipeline.

It runs the PowerShell provisioning stages 01 through 04, waits for the
unattended OS installation (stage 03) to finish, and then hands the running node
to Ansible for configuration management. Provisioning and configuration are
deliberately separate concerns -- see docs/ROADMAP.md.

Ansible runs from WSL, since there is no native Windows control node. If WSL or
Ansible is unavailable the script fails with an actionable message rather than
skipping the configuration stages silently. See docs/ANSIBLE-SETUP.md.

.PARAMETER InstallTimeoutMinutes
How long to wait for the unattended OS install to power the VM off before giving
up. Default: 20.

.PARAMETER WslDistro
The WSL distribution holding the Ansible control node. Default: "Ubuntu".
#>

param (
    [int]$InstallTimeoutMinutes = 20,
    [string]$WslDistro = "Ubuntu"
)

$ErrorActionPreference = 'Stop'
$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$TranscriptPath = Join-Path $logDir "$scriptName-$timestamp.log"
Start-Transcript -Path $TranscriptPath -Append -Force

try {

# config/node.json is the single source of truth for lab/hardware settings --
# every stage below reads the same file independently, so this just keeps
# the orchestrator's own polling logic (wipe-check, install wait-loop) in sync.
. (Join-Path $PSScriptRoot "scripts\Get-LabConfig.ps1")
$Config = Get-LabConfig -ConfigPath (Join-Path $PSScriptRoot "config\node.json")
$VmName = $Config.vm_name

Write-Output "=================================================="
Write-Output ">>> INITIATING MASTER DEPLOYMENT PIPELINE <<<"
Write-Output "=================================================="

$existingVms = & $VBoxManage list vms 2>$null
$skipProvisioning = $false

if ($existingVms -match "`"$VmName`"") {
    Write-Warning "VM '$VmName' already exists!"
    $choice = Read-Host "Do you want to WIPE IT and start fresh? (y/N)"
    if ($choice -notmatch "^[yY]") {
        Write-Output "`n[OK] Skipping Infrastructure Provisioning (Stages 01-03)..."
        Write-Output "Jumping straight to Configuration Management (Stages 04-06)."
        $skipProvisioning = $true
    }
}

if (-not $skipProvisioning) {
    # 1. Host Preparation
    Write-Output "`n>>> Executing Stage 01: Host Prep..."
    & .\scripts\01-host-prep.ps1

    # 2. Node Provisioning
    Write-Output "`n>>> Executing Stage 02: Node Provisioning..."
    & .\scripts\02-provision-node.ps1

    # 3. Automated OS Installation
    Write-Output "`n>>> Executing Stage 03: Automated OS Installation..."
    & .\scripts\03-autoinstall-node.ps1

    Write-Output "`n[WAITING] The VM is now installing Ubuntu Server in the background."
    Write-Output "[WAITING] This typically takes 5-10 minutes depending on your disk speed."
    Write-Output "[WAITING] The script will automatically resume once the VM powers itself off."

    # Wait Loop for OS Installation
    $isInstalling = $true
    $deadline = (Get-Date).AddMinutes($InstallTimeoutMinutes)
    while ($isInstalling) {
        if ((Get-Date) -gt $deadline) {
            throw "OS Installation stalled: Timeout of $InstallTimeoutMinutes minutes reached for VM '$VmName'. Transcript: $TranscriptPath"
        }
        Start-Sleep -Seconds 15
        # If the VM is deleted mid-run, showvminfo writes to stderr -- and in
        # PowerShell 5.1 that becomes an ErrorRecord which $ErrorActionPreference
        # = 'Stop' promotes to a terminating error, pre-empting the specific
        # diagnostic below. Drop to 'Continue' for the poll so the null check is
        # the thing that actually reports it.
        $ErrorActionPreference = 'Continue'
        $state = & $VBoxManage showvminfo $VmName 2>&1 | Select-String "State:"
        $ErrorActionPreference = 'Stop'
        if ($null -eq $state) {
            throw "VM '$VmName' disappeared or VBoxManage returned null during installation wait loop. Transcript: $TranscriptPath"
        }
        if ($state -match "powered off") {
            $isInstalling = $false
            Write-Output "`n[SUCCESS] OS Installation complete! VM has powered off."
        }
    }
}

# 4. Connect Node (This boots the VM and gets the IP)
Write-Output "`n>>> Executing Stage 04: Connect Node (Booting VM)..."
& .\scripts\04-connect-node.ps1

# Wait a few seconds for SSH to fully start inside the VM
Write-Output "Waiting 15 seconds for SSH daemon to initialize..."
Start-Sleep -Seconds 15

# 5. Configuration management (Ansible)
# Provisioning stops here. Everything past this point configures a Linux node
# that is already running, which is Ansible's job rather than PowerShell's --
# see docs/ROADMAP.md. Ansible has no native Windows control node, so it runs
# from WSL; docs/ANSIBLE-SETUP.md covers the one-time setup.
Write-Output "`n>>> Executing configuration management with Ansible..."

$wslExe = if (Test-Path "$env:WINDIR\sysnative\wsl.exe") { "$env:WINDIR\sysnative\wsl.exe" } else { "$env:WINDIR\System32\wsl.exe" }
if (-not (Test-Path $wslExe)) {
    throw "WSL is not installed on this host, so the configuration stages cannot run. Install it and set up an Ansible control node -- see docs/ANSIBLE-SETUP.md. The VM is provisioned and reachable; only configuration was skipped."
}

# The distro is named explicitly rather than relying on the WSL default. Docker
# Desktop registers its own WSL 2 distro, and if that is the default a bare `wsl`
# invocation starts it instead and fails with HCS_E_HYPERV_NOT_INSTALLED.
& $wslExe -d $WslDistro -- bash -c "command -v ansible-playbook" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Ansible is not installed in the '$WslDistro' WSL distro, so the configuration stages cannot run. See docs/ANSIBLE-SETUP.md. The VM is provisioned and reachable; only configuration was skipped."
}

# Translate the Windows path with wslpath rather than string surgery on the
# drive letter, so this keeps working if the repository moves.
$ansibleDirWin = (Join-Path $PSScriptRoot "ansible") -replace '\\', '/'
$ansibleDir = (& $wslExe -d $WslDistro -- wslpath -a "$ansibleDirWin").Trim()
if ($LASTEXITCODE -ne 0 -or -not $ansibleDir) {
    throw "Could not resolve '$ansibleDirWin' to a WSL path (wslpath exit $LASTEXITCODE)."
}

# ANSIBLE_CONFIG is passed explicitly because Ansible ignores an ansible.cfg
# found in a world-writable directory, and Windows drives mounted into WSL report
# mode 0777. Without it the inventory is never parsed and the play reports
# "no hosts matched" as though the inventory were at fault.
Write-Output "-> Running ansible-playbook site.yml (you will be prompted once for the sudo password)"
& $wslExe -d $WslDistro -- bash -c "cd '$ansibleDir' && ANSIBLE_CONFIG='$ansibleDir/ansible.cfg' ansible-playbook site.yml -K"
if ($LASTEXITCODE -ne 0) {
    throw "The Ansible run failed (exit $LASTEXITCODE). The node is provisioned but not fully configured. Re-run this script, or run the playbook directly -- see docs/ANSIBLE-SETUP.md."
}

Write-Output "`n=================================================="
Write-Output "[OK] PIPELINE COMPLETE"
Write-Output "Your SRE node is fully provisioned, secured, and monitored!"
Write-Output "=================================================="
} finally {
    Stop-Transcript
}

