<#
.SYNOPSIS
Installs and configures Tailscale on the headless VM node.

.DESCRIPTION
This script automatically connects to the VM via localhost port-forwarding, then uses SSH (authenticating
via your SSH key) to install Tailscale. You may be prompted once for the 'sysadmin'
account password -- that's sudo, not SSH.
Once installed, it runs 'tailscale up' and displays an authentication link. You must click this link to add the node to your Tailscale network.

#>
param ()

$logDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Start-Transcript -Path (Join-Path $logDir "$scriptName-$timestamp.log") -Append

try {
    # 1. Retrieve the IP address (Assumes VM is already running)
    $ipAddress = "127.0.0.1"

    # 2. Execute SSH Command to install Tailscale
    Write-Output "`n=================================================="
    Write-Output "Connecting to VM to install Tailscale (authenticating via SSH key)."
    Write-Output "You may be prompted once for the 'sysadmin' account password -- that's sudo, not SSH."
    Write-Output "After installation, look for the 'tailscale up' authentication link in the output!"
    Write-Output "==================================================`n"

    $sshPath = if (Test-Path "$env:WINDIR\sysnative\OpenSSH\ssh.exe") { "$env:WINDIR\sysnative\OpenSSH\ssh.exe" } else { "$env:WINDIR\System32\OpenSSH\ssh.exe" }

    # The command installs tailscale, and runs tailscale up to generate the auth link
    $sshCommand = "curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up"

    # Using ssh with -t allocates a pseudo-TTY so sudo can prompt for the password interactively.
    & $sshPath -p 2222 -t -o StrictHostKeyChecking=no sysadmin@$ipAddress $sshCommand

    # ssh returns the remote command's exit status (or 255 if the connection itself
    # failed). $ErrorActionPreference does not apply to native executables, so without
    # this check a failed install would fall straight through to the next stage and
    # the pipeline would report success over work that never happened.
    if ($LASTEXITCODE -ne 0) {
        throw "Tailscale setup failed on the node (ssh exit $LASTEXITCODE). Common causes: the install script could not reach tailscale.com, or 'tailscale up' was interrupted before the device was approved in the browser. Re-run this stage after resolving it -- the install is safe to repeat."
    }

    Write-Output "`n[OK] Tailscale is installed and the node is authenticated."
}
finally {
    Stop-Transcript
}
