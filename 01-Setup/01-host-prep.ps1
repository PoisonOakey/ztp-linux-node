<#
.SYNOPSIS
Prepares a Windows Host for Oracle VirtualBox infrastructure provisioning.

.DESCRIPTION
This script performs a complete host bootstrap:
1. Disables conflicting Type 1 hypervisors (Hyper-V) to free VT-x extensions.
2. Installs Oracle VirtualBox via winget.
3. Provisions the local lab directory and fetches the required Ubuntu Server ISO.
#>

Write-Host "Starting Stage 0: Host Environment Preparation..." -ForegroundColor Cyan

# ==============================================================================
# 1. HARDWARE LAYER: Disable Conflicting Windows Features
# ==============================================================================
$features = @("Microsoft-Hyper-V-All", "HypervisorPlatform", "VirtualMachinePlatform")

Write-Host "`n-> Securing hardware virtualization extensions..." -ForegroundColor Yellow
foreach ($feature in $features) {
    Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null
    Write-Host "   [OK] Disabled: $feature" -ForegroundColor Green
}

bcdedit /set hypervisorlaunchtype off | Out-Null
Write-Host "   [OK] BCD hypervisor launch type disabled." -ForegroundColor Green

# ==============================================================================
# 2. SOFTWARE LAYER: Install the Hypervisor
# ==============================================================================
Write-Host "`n-> Checking for Oracle VirtualBox installation..." -ForegroundColor Yellow

# Using winget to silently install or update VirtualBox
winget install -e --id Oracle.VirtualBox --accept-package-agreements --accept-source-agreements
Write-Host "   [OK] Oracle VirtualBox is present." -ForegroundColor Green

# ==============================================================================
# 3. ASSET LAYER: Fetch Infrastructure Images
# ==============================================================================
Write-Host "`n-> Provisioning lab directories and fetching assets..." -ForegroundColor Yellow

$LabDir = "$HOME\server-lab"
$IsoUrl = "https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso"
$IsoPath = "$LabDir\ubuntu-24.04.4-live-server-amd64.iso"

# Create the directory if it doesn't exist
if (!(Test-Path -Path $LabDir)) {
    New-Item -ItemType Directory -Path $LabDir -Force | Out-Null
    Write-Host "   [OK] Created directory: $LabDir" -ForegroundColor Green
}

# Download the ISO if it isn't already there
if (!(Test-Path -Path $IsoPath)) {
    Write-Host "   [*] Downloading Ubuntu Server ISO (This may take a few minutes)..." -ForegroundColor Cyan
    # Using native curl.exe for better large-file handling and redirect support in Windows
    curl.exe -O -L --output-dir $LabDir $IsoUrl
    Write-Host "   [OK] Download complete." -ForegroundColor Green
} else {
    Write-Host "   [OK] Ubuntu Server ISO already exists. Skipping download." -ForegroundColor Green
}

# ==============================================================================
# END OF SCRIPT
# ==============================================================================
Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "Host preparation complete." -ForegroundColor Green
Write-Host "CRITICAL: If Hyper-V features were modified, a system restart is REQUIRED before running Stage 1." -ForegroundColor Red
