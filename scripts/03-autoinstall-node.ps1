<#
.SYNOPSIS
Automates the Ubuntu Server OS installation by injecting cloud-init configuration via a temporary VHD.

.DESCRIPTION
This script performs a fully automated, unattended installation:
1. Validates Administrative privileges (required for virtual disk creation).
2. Generates a temporary FAT32 Virtual Hard Disk (VHD) labeled "CIDATA".
3. Injects the cloud-init user-data and meta-data configurations.
4. Attaches the configuration disk to the VirtualBox VM.
5. Boots the VM headlessly to complete the automated OS installation.

.PARAMETER VmName
Name of the Virtual Machine. Default: "SRE-Node-01"

.PARAMETER LabDir
The directory where the VM disk and ISO are stored. Default: "$HOME\server-lab"
#>
param (
    [string]$VmName = "SRE-Node-01",
    [string]$LabDir = "$HOME\server-lab"
)

$logDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Start-Transcript -Path (Join-Path $logDir "$scriptName-$timestamp.log") -Append

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

# ==============================================================================
# 1. Generate the CIDATA Virtual Disk
# ==============================================================================
Write-Output "`n-> Generating temporary cloud-init configuration disk..."

if (Test-Path $CidataPath) {
    # Attempt to detach it just in case a previous run crashed
    $detachScript = @"
select vdisk file="$CidataPath"
detach vdisk
"@
    $detachScript | diskpart.exe | Out-Null
    Remove-Item -Path $CidataPath -Force -ErrorAction SilentlyContinue
}

# We use diskpart to create a dynamically expanding 10MB VHD, format it FAT32, and assign a drive letter.
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
Copy-Item -Path (Join-Path $CloudInitDir "user-data") -Destination $MountDir -Force
Copy-Item -Path (Join-Path $CloudInitDir "meta-data") -Destination $MountDir -Force

# Small sleep to ensure file locks are released
Start-Sleep -Seconds 1

Write-Output "-> Safely unmounting configuration disk..."
$diskpartUnmount = @"
select vdisk file="$CidataPath"
detach vdisk
"@
$diskpartUnmount | diskpart.exe | Out-Null

# ==============================================================================
# 3. Attach Disk and Boot VM
# ==============================================================================
Write-Output "`n-> Attaching configuration disk to VM..."
# We attach it to the SATA controller on port 1 (port 0 is the main OS disk)
& $VBoxManage storageattach $VmName --storagectl "SATA Controller" --port 1 --device 0 --type hdd --medium $CidataPath

Write-Output "-> Booting VM with GUI for automated installation monitoring..."
& $VBoxManage startvm $VmName --type gui

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

Stop-Transcript
