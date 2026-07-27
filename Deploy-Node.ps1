<#
.SYNOPSIS
Master execution script that runs all stages sequentially to fully bootstrap the node.

.DESCRIPTION
This script acts as the orchestrator for the entire SysOps pipeline.
It handles running scripts 01 through 06, and critically, it pauses and waits 
for the unattended OS installation (Stage 03) to complete before moving on to 
networking and observability.
#>

$ErrorActionPreference = 'Stop'
$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$VmName = "SRE-Node-01"

Write-Output "=================================================="
Write-Output "ðŸš€ INITIATING MASTER DEPLOYMENT PIPELINE ðŸš€"
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
    while ($isInstalling) {
        Start-Sleep -Seconds 15
        $state = & $VBoxManage showvminfo $VmName 2>$null | Select-String "State:"
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
Write-Output "ðŸŽ‰ PIPELINE COMPLETE ðŸŽ‰"
Write-Output "Your SRE node is fully provisioned, secured, and monitored!"
Write-Output "=================================================="
