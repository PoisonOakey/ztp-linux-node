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

# Network Adapter Auto-Detection
Write-Output "`n-> Detecting active network adapters for bridging..."
$activeAdapters = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false })
if (-not $activeAdapters) {
    Write-Error "No active physical network adapters found to bridge."
    exit 1
}

$BridgeAdapter = ""
if ($activeAdapters.Count -eq 1) {
    $BridgeAdapter = $activeAdapters[0].InterfaceDescription
    Write-Output "   [OK] Auto-selected adapter: $BridgeAdapter"
} else {
    Write-Output "   Multiple active adapters found:"
    for ($i=0; $i -lt $activeAdapters.Count; $i++) {
        Write-Output "   [$($i+1)] $($activeAdapters[$i].InterfaceDescription) - $($activeAdapters[$i].Name)"
    }
    $selection = Read-Host "   Select the adapter to use for bridging (1-$($activeAdapters.Count))"
    $selectedIndex = [int]$selection - 1
    if ($selectedIndex -ge 0 -and $selectedIndex -lt $activeAdapters.Count) {
        $BridgeAdapter = $activeAdapters[$selectedIndex].InterfaceDescription
        Write-Output "   [OK] Selected adapter: $BridgeAdapter"
    } else {
        Write-Error "Invalid selection."
        exit 1
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

# 3. Configure Network Bridging
Write-Output "-> Bridging network interface to '$BridgeAdapter'..."
& $VBoxManage modifyvm $VmName --nic1 bridged --bridgeadapter1 $BridgeAdapter

# 4. Provision Storage and Mount Media
if (Test-Path $DiskPath) {
    Write-Output "-> Removing existing stale VDI disk..."
    Remove-Item -Path $DiskPath -Force
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
Write-Output "Deployment triggered successfully."
Write-Output "NOTE: To complete the Ubuntu Server installation, you should boot it with a GUI first:"
Write-Output "    & `"$VBoxManage`" startvm `"$VmName`" --type gui"
Write-Output "Or if using an autoinstall ISO, you can boot it headlessly:"
Write-Output "    & `"$VBoxManage`" startvm `"$VmName`" --type headless"
Write-Output "Once the OS is installed, you can find its IP by checking your router or running:"
Write-Output "    & `"$VBoxManage`" guestproperty enumerate `"$VmName`""
