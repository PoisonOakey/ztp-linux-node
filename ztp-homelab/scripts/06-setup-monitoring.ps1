<#
.SYNOPSIS
Installs Docker and deploys the Prometheus/Grafana monitoring stack on the VM.

.DESCRIPTION
This script queries the VM for its IP address, uses SCP to securely copy the 
local 'monitoring' directory to the VM, and then uses SSH to install Docker 
and start the containers via Docker Compose.

.PARAMETER VmName
Name of the Virtual Machine. Default: "SRE-Node-01"
#>
param (
    [string]$VmName = "SRE-Node-01"
)

$logDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Start-Transcript -Path (Join-Path $logDir "$scriptName-$timestamp.log") -Append

$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

# 1. Retrieve the IP address
$ipAddress = "127.0.0.1"

# 2. SCP the monitoring directory to the VM
Write-Output "`n=================================================="
Write-Output "Copying monitoring configuration to the VM..."
Write-Output "When prompted, enter the password (default: 'sysadmin')"
Write-Output "==================================================`n"

$monitoringDir = Join-Path $PSScriptRoot "..\monitoring"
$scpPath = if (Test-Path "$env:WINDIR\sysnative\OpenSSH\scp.exe") { "$env:WINDIR\sysnative\OpenSSH\scp.exe" } else { "$env:WINDIR\System32\OpenSSH\scp.exe" }
# Copy the monitoring directory to the home directory of sysadmin on the VM
& $scpPath -P 2222 -r -o StrictHostKeyChecking=no $monitoringDir sysadmin@$ipAddress`:~/

# 3. SSH in to install Docker and start the stack
Write-Output "`n=================================================="
Write-Output "Installing Docker and starting Prometheus/Grafana..."
Write-Output "When prompted, enter the password again (default: 'sysadmin')"
Write-Output "==================================================`n"

$sshCommand = @"
sudo dpkg --configure -a || true && \
sudo apt-get update && \
sudo apt-get install -y docker.io docker-compose-v2 && \
sudo systemctl enable --now docker && \
cd ~/monitoring && \
sudo docker compose up -d
"@

$sshPath = if (Test-Path "$env:WINDIR\sysnative\OpenSSH\ssh.exe") { "$env:WINDIR\sysnative\OpenSSH\ssh.exe" } else { "$env:WINDIR\System32\OpenSSH\ssh.exe" }
& $sshPath -p 2222 -t -o StrictHostKeyChecking=no sysadmin@$ipAddress $sshCommand

Write-Output "`n=================================================="
Write-Output "[OK] Monitoring Stack Deployed!"
Write-Output "Grafana is running at: http://localhost:3000 (Login: admin / sysadmin)"
Write-Output "Prometheus is running at: http://localhost:9090"
Write-Output "(Or access them securely via your new Tailscale IP!)"
Write-Output "=================================================="

Stop-Transcript
