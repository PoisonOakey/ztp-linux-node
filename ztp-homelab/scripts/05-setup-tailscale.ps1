<#
.SYNOPSIS
Installs and configures Tailscale on the headless VM node.

.DESCRIPTION
This script automatically queries the VM for its local IP, then uses SSH to install Tailscale.
It will prompt you for the SSH password ('sysadmin' by default). 
Once installed, it runs 'tailscale up' and displays an authentication link. You must click this link to add the node to your Tailscale network.

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

# 1. Retrieve the IP address (Assumes VM is already running)
$ipAddress = "127.0.0.1"

# 2. Execute SSH Command to install Tailscale
Write-Output "`n=================================================="
Write-Output "Connecting to VM to install Tailscale."
Write-Output "When prompted, enter the password (default: 'sysadmin')"
Write-Output "After installation, look for the 'tailscale up' authentication link in the output!"
Write-Output "==================================================`n"

$sshPath = if (Test-Path "$env:WINDIR\sysnative\OpenSSH\ssh.exe") { "$env:WINDIR\sysnative\OpenSSH\ssh.exe" } else { "$env:WINDIR\System32\OpenSSH\ssh.exe" }

# The command installs tailscale, and runs tailscale up to generate the auth link
$sshCommand = "curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up"

# Using ssh with -t allocates a pseudo-TTY so sudo can prompt for the password interactively.
& $sshPath -p 2222 -t -o StrictHostKeyChecking=no sysadmin@$ipAddress $sshCommand

Stop-Transcript
