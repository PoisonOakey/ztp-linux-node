<#
.SYNOPSIS
Retrieves the IP address of the provisioned node and provides the SSH connection command.

.DESCRIPTION
This script checks if the VM is running. If not, it boots it headlessly.
It then queries the VirtualBox Guest Properties to discover the IP address assigned by your local DHCP server and outputs the exact command needed to SSH into the box.

.PARAMETER VmName
Name of the Virtual Machine. Default: "SRE-Node-01"
#>
param (
    [string]$VmName = "SRE-Node-01"
)

$VBoxManage = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

# 1. Ensure VM is running
$state = & $VBoxManage showvminfo $VmName | Select-String "State:"
if ($state -match "powered off") {
    Write-Output "VM is currently powered off. Booting headlessly..."
    & $VBoxManage startvm $VmName --type headless
    Write-Output "Waiting for OS to boot (this may take a minute)..."
    Start-Sleep -Seconds 15
}

# 2. Wait for Guest Additions to report an IP address
Write-Output "Querying VM for IP Address (requires Guest Additions / VM Network to be fully up)..."
$ipAddress = $null
$maxRetries = 20
$retryCount = 0

while (-not $ipAddress -and $retryCount -lt $maxRetries) {
    $guestProperties = & $VBoxManage guestproperty enumerate $VmName

    # Extract the IPv4 address. Usually found under /VirtualBox/GuestInfo/Net/0/V4/IP
    $ipMatch = $guestProperties | Select-String "Name: /VirtualBox/GuestInfo/Net/[0-9]+/V4/IP, value: ([\d\.]+)"

    if ($ipMatch) {
        $ipAddress = $ipMatch.Matches.Groups[1].Value
        break
    }

    Write-Output "IP not yet available, retrying in 5 seconds... ($($retryCount+1)/$maxRetries)"
    Start-Sleep -Seconds 5
    $retryCount++
}

if ($ipAddress) {
    Write-Output "`n=================================================="
    Write-Output "[OK] VM is actively running at IP: $ipAddress"
    Write-Output "You can now connect to your headless node!"
    Write-Output "Run the following command:"
    Write-Output "`n    ssh sysadmin@$ipAddress"
    Write-Output "`n(Default password is 'sysadmin')"
    Write-Output "=================================================="
} else {
    Write-Error "Could not retrieve IP address. Ensure the VM has finished the OS installation and has rebooted."
}
