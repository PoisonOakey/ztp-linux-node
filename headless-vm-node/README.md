# Headless VM Node

>This ia an automated sysops repository for bootstrapping a headless VirtualBox Ubuntu Server node on a Windows host.

This setup process has been automated using PowerShell scripts to ensure idempotency and sysops best practices. All scripts are located in the `scripts/` directory.

---

## 🪟 Stage 0: Host Environment Preparation

This script prepares your Windows host for VirtualBox virtualization by disabling conflicting Hyper-V features, installing VirtualBox via `winget`, and downloading the Ubuntu Server ISO.

> [!CAUTION]
> **This script requires Administrator privileges.**
> If any Hyper-V features are disabled during this step, a system restart is required before proceeding to Stage 1.
> 
> **CRITICAL ISO WARNING**: This script downloads a 3.4 GB Ubuntu ISO. If the download is interrupted, it may result in a partially downloaded ISO that will cause the automated installation in Stage 2 to fail with an `Input/output error`. Always verify the ISO downloaded completely! See [TROUBLESHOOTING.md](file:///d:/headless-vm-node/TROUBLESHOOTING.md) for details.

**Open PowerShell as Administrator** and execute:
```powershell
.\scripts\01-host-prep.ps1
```

---

## 🚀 Stage 1: Node Provisioning

This script provisions the VirtualBox VM, configures the network bridge, creates the virtual disk, and attaches the Ubuntu Server ISO. It will automatically detect your active physical network adapter, or prompt you to select one if multiple are found.

**Open PowerShell** and execute:
```powershell
.\scripts\02-provision-node.ps1
```

---

## 🤖 Stage 2: Automated OS Installation

This script injects a `cloud-init` configuration into the VM using a temporary virtual disk, completely automating the Ubuntu Server setup process without any manual GUI interaction.

> [!CAUTION]
> **This script requires Administrator privileges.**
> The script needs to mount a temporary virtual disk to inject the configuration.

**Open PowerShell as Administrator** and execute:
```powershell
.\scripts\03-autoinstall-node.ps1
```

> [!TIP]
> **Background Installation**
> The VM will boot headlessly in the background. Depending on your internet speed, the installation usually takes 5-10 minutes.
> Once the installation is complete, the VM will **automatically power off**.

You can check the installation progress by querying the VM's state. When it says `powered off`, the installation is complete:
```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" showvminfo "SRE-Node-01" | Select-String "State"
```

---

## 🔌 Stage 3: Connecting to the Node

Once the automated installation is finished and the VM is powered off, you can use the connection script. This script will boot the VM headlessly, automatically query VirtualBox for the dynamically assigned IP address, and provide you with the SSH command.

**Open PowerShell** and execute:
```powershell
.\scripts\04-connect-node.ps1
```

Once connected, you can start using your new server!
- **Default Username:** `sysadmin`
- **Default Password:** `sysadmin`

---
