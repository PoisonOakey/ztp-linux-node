<#
.SYNOPSIS
Prepares a Windows Host for Oracle VirtualBox infrastructure provisioning.

.DESCRIPTION
This script performs a complete host bootstrap:
1. Validates Administrative privileges.
2. Disables conflicting Type 1 hypervisors (Hyper-V) to free VT-x extensions.
3. Installs Oracle VirtualBox via winget.
4. Provisions the local lab directory and fetches the required Ubuntu Server ISO.

.PARAMETER LabDir
The directory where the VM and ISO will be stored. Defaults to "$HOME\server-lab".

.PARAMETER IsoUrl
URL to the Ubuntu Server ISO. Defaults to Ubuntu 24.04.4.
#>

param (
    [string]$LabDir = "$HOME\server-lab",
    [string]$IsoUrl = "https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso"
)

# 0. Validate Administrative Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires Administrator privileges. Please run PowerShell as Administrator."
    exit 1
}

Write-Output "Starting Stage 0: Host Environment Preparation..."

# ==============================================================================
# 1. HARDWARE LAYER: Disable Conflicting Windows Features
# ==============================================================================
$features = @("Microsoft-Hyper-V-All", "HypervisorPlatform", "VirtualMachinePlatform")
$requiresRestart = $false

Write-Output "`n-> Securing hardware virtualization extensions..."
foreach ($feature in $features) {
    try {
        $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction Stop
        if ($featureState.State -eq 'Enabled') {
            Write-Output "   [*] Disabling: $feature..."
            Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction Stop | Out-Null
            Write-Output "   [OK] Disabled: $feature"
            $requiresRestart = $true
        } else {
            Write-Output "   [OK] Already disabled: $feature"
        }
    } catch {
        Write-Warning "   [!] Could not check or modify feature $feature. It might not be available on this OS edition."
    }
}

try {
    # Check current BCD state to be idempotent
    $bcdState = bcdedit /enum '{current}' | Select-String "hypervisorlaunchtype"
    if ($bcdState -match "Off") {
        Write-Output "   [OK] BCD hypervisor launch type is already disabled."
    } else {
        Write-Output "   [*] Disabling BCD hypervisor launch type..."
        bcdedit /set hypervisorlaunchtype off | Out-Null
        Write-Output "   [OK] BCD hypervisor launch type disabled."
        $requiresRestart = $true
    }
} catch {
    Write-Warning "   [!] Failed to modify BCD hypervisorlaunchtype."
}

# ==============================================================================
# 2. SOFTWARE LAYER: Install the Hypervisor
# ==============================================================================
Write-Output "`n-> Checking for Oracle VirtualBox installation..."

if (Get-Command "VBoxManage.exe" -ErrorAction SilentlyContinue) {
    Write-Output "   [OK] Oracle VirtualBox is already installed and in PATH."
} else {
    Write-Output "   [*] Installing VirtualBox via winget..."
    try {
        # Using winget to silently install or update VirtualBox
        winget install -e --id Oracle.VirtualBox --accept-package-agreements --accept-source-agreements --silent
        Write-Output "   [OK] Oracle VirtualBox installed."
    } catch {
        Write-Error "   [X] Failed to install VirtualBox. Please install it manually."
        exit 1
    }
}

# ==============================================================================
# 3. ASSET LAYER: Fetch Infrastructure Images
# ==============================================================================
Write-Output "`n-> Provisioning lab directories and fetching assets..."

$IsoFileName = Split-Path $IsoUrl -Leaf
$IsoPath = Join-Path $LabDir $IsoFileName

# Create the directory if it doesn't exist
if (-not (Test-Path -Path $LabDir)) {
    New-Item -ItemType Directory -Path $LabDir -Force | Out-Null
    Write-Output "   [OK] Created directory: $LabDir"
}

# Download the ISO if it isn't already there
if (-not (Test-Path -Path $IsoPath)) {
    Write-Output "   [*] Downloading $IsoFileName (This may take a few minutes)..."
    try {
        # Using native curl.exe for better large-file handling and redirect support in Windows
        curl.exe -O -L --output-dir $LabDir $IsoUrl
        if ($LASTEXITCODE -eq 0) {
            Write-Output "   [OK] Download complete."
        } else {
            throw "curl.exe exited with code $LASTEXITCODE"
        }
    } catch {
        Write-Error "   [X] Failed to download ISO: $_"
        exit 1
    }
} else {
    Write-Output "   [OK] $IsoFileName already exists. Skipping download."
}

# ==============================================================================
# END OF SCRIPT
# ==============================================================================
Write-Output "`n=================================================="
Write-Output "Host preparation complete."
if ($requiresRestart) {
    Write-Output "CRITICAL: Hyper-V features were modified. A system restart is REQUIRED before running Stage 1."
    Write-Output "Please restart your computer now."
} else {
    Write-Output "System is ready for Stage 1. No restart required."
}
