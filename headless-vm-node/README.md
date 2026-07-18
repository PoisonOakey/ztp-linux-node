# Headless VM Node

Automated sysops repository for bootstrapping a headless VirtualBox Ubuntu Server node on a Windows host.

## Quick Start

This setup process has been automated using PowerShell scripts to ensure idempotency and sysops best practices. All scripts are located in the `scripts/` directory.

### 🪟 Stage 0: Host Environment Preparation

This script prepares your Windows host for VirtualBox virtualization by disabling conflicting Hyper-V features, installing VirtualBox via `winget`, and downloading the Ubuntu Server ISO.

> [!CAUTION]
> **This script requires Administrator privileges.**
> If any Hyper-V features are disabled during this step, a system restart is required before proceeding to Stage 1.

**Open PowerShell as Administrator** and execute:
```powershell
.\scripts\01-host-prep.ps1
```

<br>

### 🚀 Stage 1: Node Provisioning

This script provisions the VirtualBox VM, configures the network bridge, creates the virtual disk, and attaches the Ubuntu Server ISO. It will automatically detect your active physical network adapter, or prompt you to select one if multiple are found.

**Open PowerShell** and execute:
```powershell
.\scripts\02-provision-node.ps1
```

> [!TIP]
> **OS Installation**
> By default, the script provisions the VM architecture. To complete the Ubuntu Server installation, you will need to boot the VM in GUI mode for the very first time:
> ```powershell
> & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm "SRE-Node-01" --type gui
> ```
> Follow the on-screen prompts to install Ubuntu Server. Once installed, you can shut it down and boot it headlessly in the future.
