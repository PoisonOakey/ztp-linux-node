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

$logDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Start-Transcript -Path (Join-Path $logDir "$scriptName-$timestamp.log") -Append

# 0. Validate Administrative Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires Administrator privileges. Please run PowerShell as Administrator."
    exit 1
}

Write-Output "Starting Stage 1: Host Environment Preparation..."

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
        }
        else {
            Write-Output "   [OK] Already disabled: $feature"
        }
    }
    catch {
        Write-Warning "   [!] Could not check or modify feature $feature. It might not be available on this OS edition."
    }
}

try {
    # Resolve bcdedit path (handle 32-bit PowerShell on 64-bit OS)
    $bcdeditPath = if (Test-Path "$env:windir\sysnative\bcdedit.exe") { "$env:windir\sysnative\bcdedit.exe" } else { "$env:windir\System32\bcdedit.exe" }

    # Check current BCD state to be idempotent.
    # NOTE: deliberately not passing an entry ID (e.g. "{current}") here --
    # PowerShell's native-argument marshalling mangles curly-brace tokens like
    # that, so bcdedit sees a malformed argument and returns "The specified
    # entry type is invalid" instead of real data. That makes this check
    # always fail closed, so the script re-disables (and re-demands a reboot
    # for) a setting that was already off. Bare /enum lists the active boot
    # entries by default, which is sufficient and avoids the bad argument
    # entirely -- matches how /set below already omits the ID for the same reason.
    $bcdState = & $bcdeditPath /enum | Select-String "hypervisorlaunchtype"
    if ($bcdState -match "Off") {
        Write-Output "   [OK] BCD hypervisor launch type is already disabled."
    }
    else {
        Write-Output "   [*] Disabling BCD hypervisor launch type..."
        & $bcdeditPath /set hypervisorlaunchtype off | Out-Null
        Write-Output "   [OK] BCD hypervisor launch type disabled."
        $requiresRestart = $true
    }
}
catch {
    Write-Warning "   [!] Failed to modify BCD hypervisorlaunchtype: $($_.Exception.Message)"
}

# ==============================================================================
# 2. SOFTWARE LAYER: Install the Hypervisor
# ==============================================================================
Write-Output "`n-> Checking for Oracle VirtualBox installation..."

if (Get-Command "VBoxManage.exe" -ErrorAction SilentlyContinue) {
    Write-Output "   [OK] Oracle VirtualBox is already installed and in PATH."
}
else {
    Write-Output "   [*] Installing VirtualBox via winget..."
    try {
        # Using winget to silently install or update VirtualBox
        winget install -e --id Oracle.VirtualBox --accept-package-agreements --accept-source-agreements --silent
        Write-Output "   [OK] Oracle VirtualBox installed."
    }
    catch {
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
        }
        else {
            throw "curl.exe exited with code $LASTEXITCODE"
        }
    }
    catch {
        Write-Error "   [X] Failed to download ISO: $_"
        exit 1
    }
}
else {
    Write-Output "   [OK] $IsoFileName already exists. Skipping download."
}

# ==============================================================================
# END OF SCRIPT
# ==============================================================================
Write-Output "`n=================================================="
Write-Output "Host preparation complete."
if ($requiresRestart) {
    Write-Output "CRITICAL: Hyper-V features were modified. A system restart is REQUIRED before running Stage 2."
    Stop-Transcript
    throw "Please restart your computer now, and then run Deploy-Node.ps1 again."
}
else {
    Write-Output "System is ready for Stage 2. No restart required."
}

Stop-Transcript
