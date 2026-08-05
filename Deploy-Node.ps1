<#
.SYNOPSIS
Master execution script that runs all stages sequentially to fully bootstrap the node.

.DESCRIPTION
This script acts as the orchestrator for the entire SysOps pipeline.
It handles running scripts 01 through 06, and critically, it pauses and waits 
for the unattended OS installation (Stage 03) to complete before moving on to 
networking and observability.
#>

param (
    [int]$InstallTimeoutMinutes = 20
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

# 5. Tailscale Setup
Write-Output "`n>>> Executing Stage 05: Tailscale Setup..."
& .\scripts\05-setup-tailscale.ps1

# 6. Monitoring Setup
Write-Output "`n>>> Executing Stage 06: Monitoring Setup..."
& .\scripts\06-setup-monitoring.ps1

Write-Output "`n=================================================="
Write-Output "[OK] PIPELINE COMPLETE"
Write-Output "Your SRE node is fully provisioned, secured, and monitored!"
Write-Output "=================================================="
} finally {
    Stop-Transcript
}

