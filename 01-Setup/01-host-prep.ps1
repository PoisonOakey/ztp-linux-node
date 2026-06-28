Write-Host "Starting Host Environment Preparation..." -ForegroundColor Cyan

# 1. Disable Windows Optional Features
$features = @("Microsoft-Hyper-V-All", "HypervisorPlatform", "VirtualMachinePlatform")

foreach ($feature in $features) {
    Write-Host "Disabling feature: $feature" -ForegroundColor Yellow
    Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart | Out-Null
    Write-Host "[OK] $feature disabled." -ForegroundColor Green
}

# 2. Disable Hypervisor at Boot Level
Write-Host "Modifying BCD to disable hypervisor launch type..." -ForegroundColor Yellow
bcdedit /set hypervisorlaunchtype off | Out-Null
Write-Host "[OK] BCD configuration updated." -ForegroundColor Green

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Host preparation complete. A system restart is REQUIRED to release hardware locks." -ForegroundColor Red
Write-Host "Please restart your machine before running the Stage 1 provisioning script." -ForegroundColor Yellow
