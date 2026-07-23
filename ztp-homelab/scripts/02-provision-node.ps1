<#
.SYNOPSIS
Automates the provisioning of a VirtualBox Ubuntu Server node.

.DESCRIPTION
This script provisions a VirtualBox VM with proper resources,
automatically detects and configures the bridged network adapter,
creates a virtual disk, and attaches the Ubuntu ISO.

.PARAMETER VmName
Name of the Virtual Machine. Default: "SRE-Node-01"

.PARAMETER LabDir
The directory where the VM disk and ISO are stored. Default: "$HOME\server-lab"

.PARAMETER IsoName
The name of the Ubuntu ISO file. Default: "ubuntu-24.04.4-live-server-amd64.iso"
#>
param (
    [string]$VmName = "SRE-Node-01",
    [string]$LabDir = "$HOME\server-lab",
    [string]$IsoName = "ubuntu-24.04.4-live-server-amd64.iso",
    [int]$RamMb = 4096,
    [int]$CpuCores = 2,
    [int]$DiskSizeMb = 25600
)

$logDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Start-Transcript -Path (Join-Path $logDir "$scriptName-$timestamp.log") -Append

$ErrorActionPreference = 'Stop'

Write-Output "Starting Stage 2: Node Provisioning for $VmName..."

# Resolve VBoxManage Path
$VBoxManage = "VBoxManage.exe"
if (-not (Get-Command $VBoxManage -ErrorAction SilentlyContinue)) {
    # Check default install locations
    $defaultPath = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
    if (Test-Path $defaultPath) {
        $VBoxManage = $defaultPath
    } else {
        Write-Error "VBoxManage.exe not found in PATH or default installation directory. Is VirtualBox installed?"
        exit 1
    }
}

# Check if VM already exists
$existingVms = & $VBoxManage list vms
if ($existingVms -match "`"$VmName`"") {
    Write-Warning "Virtual Machine '$VmName' already exists!"
    $choice = Read-Host "Do you want to delete it and recreate? (y/N)"
    if ($choice -match "^[yY]") {
        Write-Output "-> Unregistering and deleting existing VM..."
        & $VBoxManage unregistervm $VmName --delete
    } else {
        Write-Output "Operation aborted by user."
        exit 0
    }
}



$IsoPath = Join-Path $LabDir $IsoName
$DiskPath = Join-Path $LabDir "$VmName.vdi"

if (-not (Test-Path $IsoPath)) {
    Write-Error "ISO file not found at $IsoPath. Please run Stage 1 first."
    exit 1
}

# 1. Create and Register the VM Shell
Write-Output "`n-> Creating Virtual Machine architecture..."
& $VBoxManage createvm --name $VmName --ostype "Ubuntu_64" --register

# 2. Allocate Hardware Resources
Write-Output "-> Allocating $CpuCores vCPUs and ${RamMb}MB RAM..."
& $VBoxManage modifyvm $VmName --memory $RamMb --cpus $CpuCores

# 3. Configure Network NAT and Port Forwarding
Write-Output "-> Configuring NAT with Virtio performance driver and Port Forwarding (Host 2222 -> Guest 22)..."
& $VBoxManage modifyvm $VmName --nic1 nat --nictype1 virtio
& $VBoxManage modifyvm $VmName --natpf1 "guestssh,tcp,,2222,,22"
& $VBoxManage modifyvm $VmName --natpf1 "grafana,tcp,,3000,,3000"
& $VBoxManage modifyvm $VmName --natpf1 "prometheus,tcp,,9090,,9090"

# 4. Provision Storage and Mount Media
if (Test-Path $DiskPath) {
    Write-Output "-> Removing existing stale VDI disk..."
    & $VBoxManage closemedium disk $DiskPath --delete 2>$null
    if (Test-Path $DiskPath) { Remove-Item -Path $DiskPath -Force }
}

Write-Output "-> Provisioning ${DiskSizeMb}MB Storage Drive..."
& $VBoxManage createmedium disk --filename $DiskPath --size $DiskSizeMb

Write-Output "-> Attaching SATA Controller..."
& $VBoxManage storagectl $VmName --name "SATA Controller" --add sata --controller IntelAHCI
& $VBoxManage storageattach $VmName --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium $DiskPath

Write-Output "-> Attaching IDE Controller and Mounting ISO..."
& $VBoxManage storagectl $VmName --name "IDE Controller" --add ide
& $VBoxManage storageattach $VmName --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium $IsoPath

# 5. Provide next steps (Booting headless by default, but warning about OS install)
Write-Output "`n=================================================="
Write-Output "`n=================================================="
Write-Output "Deployment triggered successfully."
Write-Output "To complete the automated headless OS installation, please run:"
Write-Output "    .\scripts\03-autoinstall-node.ps1"
Write-Output "=================================================="

Stop-Transcript
