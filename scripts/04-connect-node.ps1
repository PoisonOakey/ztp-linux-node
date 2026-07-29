<#
.SYNOPSIS
Retrieves the IP address of the provisioned node and provides the SSH connection command.

.DESCRIPTION
This script checks if the VM is running. If not, it boots it headlessly.
It then queries the VirtualBox Guest Properties to discover the IP address assigned by your local DHCP server and outputs the exact command needed to SSH into the box.

.PARAMETER VmName
Name of the Virtual Machine. Defaults to the value in config/node.json.
#>
param (
    [string]$VmName
)

# config/node.json is the single source of truth for lab/hardware settings;
# an explicit -VmName argument still overrides it for one-off runs.
. (Join-Path $PSScriptRoot "Get-LabConfig.ps1")
$Config = Get-LabConfig -ConfigPath (Join-Path $PSScriptRoot "..\config\node.json")
if (-not $VmName) { $VmName = $Config.vm_name }

$logDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Start-Transcript -Path (Join-Path $logDir "$scriptName-$timestamp.log") -Append

$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

# 1. Ensure VM is running
$state = & $VBoxManage showvminfo $VmName | Select-String "State:"
if ($state -match "powered off") {
    Write-Output "VM is currently powered off. Booting headlessly..."
    & $VBoxManage startvm $VmName --type headless
    Write-Output "Waiting for OS to boot (this may take a minute)..."
    Start-Sleep -Seconds 15
}

# 2. Wait for SSH Port Forwarding to become active
Write-Output "Waiting for VM to expose SSH on localhost:2222..."
$maxRetries = 20
$retryCount = 0
$sshReady = $false

while (-not $sshReady -and $retryCount -lt $maxRetries) {
    try {
        $tcpConnection = New-Object System.Net.Sockets.TcpClient
        $tcpConnection.Connect("127.0.0.1", 2222)
        if ($tcpConnection.Connected) {
            $sshReady = $true
            $tcpConnection.Close()
            break
        }
    } catch {
        Write-Verbose "Port not ready yet."
    }
    
    Write-Output "SSH not yet available, retrying in 3 seconds... ($($retryCount+1)/$maxRetries)"
    Start-Sleep -Seconds 3
    $retryCount++
}

if ($sshReady) {
    # Provide the unified connection string
    $ipAddress = "127.0.0.1"
    
    # We write 127.0.0.1 to the cache so the other scripts can read it if needed,
    # though they will just hardcode 127.0.0.1 and port 2222.
    $ipCacheFile = Join-Path $env:TEMP ".sre-node-ip.txt"
    Set-Content -Path $ipCacheFile -Value $ipAddress
    
    Write-Output "`n=================================================="
    Write-Output "[OK] VM is actively running and forwarded to localhost!"
    Write-Output "You can now connect to your headless node!"
    Write-Output "Run the following command:"
    Write-Output "`n    ssh -p 2222 sysadmin@127.0.0.1"
    Write-Output "`n(Authenticates via your SSH key -- no password needed. See TROUBLESHOOTING.md #10 if that ever fails.)"
    Write-Output "=================================================="
} else {
    Write-Error "Could not connect to localhost:2222. Ensure the VM has finished booting."
}

Stop-Transcript
