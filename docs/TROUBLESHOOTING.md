# Troubleshooting Guide

>This document captures the known issues, edge cases, and sysops debugging efforts encountered while building this automated VirtualBox provisioner. If you run into bizarre behavior during the installation, check here first.

---

## 1. The "Truncated ISO" / Hash Sum Mismatch Bug

**Symptoms:**
- The automated installation (`03-autoinstall-node.ps1`) crashes midway through.
- If you check the background VM screen, it's frozen on a Subiquity error log.
- Extracting the Python traceback reveals `apt-get install grub-pc` failing with:
  ```text
  Err:8 file:/cdrom noble/main amd64 os-prober amd64 1.81ubuntu4
    Hash Sum mismatch
  E: Read error - read (5: Input/output error)
  ```

**Root Cause:**
The `01-host-prep.ps1` script uses `curl.exe` (or `Invoke-WebRequest`) to download the Ubuntu ISO. If your internet connection drops or times out during this 3.4 GB download, the file will be saved partially (e.g., stopping at 2.4 GB). However, since the file exists on the disk, subsequent runs of `01-host-prep.ps1` will assume it was successfully downloaded and skip fetching it.
VirtualBox will mount this truncated ISO without complaining. The boot files at the start of the ISO work perfectly, but as soon as the installer reaches the end of the filesystem to extract packages like `os-prober` or `grub-pc`, it hits a physical end-of-file I/O error and crashes the entire installation.

**Resolution:**
Always verify the SHA256 checksum of the downloaded ISO. If you encounter this bug:
1. Delete the corrupted ISO from your lab directory (`$HOME\server-lab\*.iso`).
2. Re-run `01-host-prep.ps1` and ensure the download reaches 100% (approx 3.4 GB).

---

## 2. VirtualBox UEFI Firmware Boot Loop

**Symptoms:**
- Switching the VM's firmware from standard BIOS to UEFI (`--firmware efi`) causes the VM to drop into the `UEFI Interactive Shell v2.2` instead of booting the Ubuntu ISO.
- Manually navigating the UEFI file system (`FS0:\EFI\BOOT\BOOTX64.EFI`) allows the ISO to boot, but automation is completely broken.

**Root Cause:**
VirtualBox's UEFI implementation is notoriously finicky with Linux ISOs. By default, it expects the EFI bootloaders to be in a highly specific path and fails to automatically fall back to the CD-ROM EFI partition in certain unattended scenarios.

**Resolution:**
For optimal automation compatibility, this project explicitly forces **Standard BIOS** (`--firmware bios`). Ubuntu Server's autoinstaller fully supports BIOS installations, and it circumvents the VirtualBox UEFI bootloader bugs entirely.

---

## 3. The Interactive `grub-pc` Prompt (Unattended Block)

**Symptoms:**
- During an automated Ubuntu installation on a Standard BIOS system, the installation pauses indefinitely.
- Viewing the VM screen reveals a purple `debconf` prompt asking the user which disk to install the GRUB bootloader to (e.g., `/dev/sda`).
- This completely breaks the "headless" and "unattended" nature of the script.

**Root Cause:**
When installing via legacy BIOS, the `grub-pc` package is updated or installed. By default, `debconf` notices it is a new installation and defensively prompts the user to confirm the Master Boot Record (MBR) disk location to avoid overwriting existing bootloaders.

**Resolution:**
We bypass this interactive prompt by injecting `debconf_selections` directly into the `user-data` file. This pre-answers the prompt for the installer:
```yaml
user-data:
  debconf_selections: |
    grub-pc grub-pc/install_devices multiselect /dev/sda
```
This forces `grub-pc` to silently install to `/dev/sda` without hanging the installation.

---

## 4. The Silent IPv6 / Apt-Get Mirror Hang

**Symptoms:**
- The automated installation proceeds normally but gets permanently stuck on the `installing kernel` step.
- The VM's CPU usage might sit around 0% for the installation processes.
- Jumping into the hidden installer terminal (TTY2 via `Alt+F2`) and running `ps auxf` reveals that the `apt-get` process is running `/usr/lib/apt/methods/http`, but has accumulated zero recent CPU time and is completely hung.

**Root Cause:**
By default, Ubuntu's installer attempts to connect to `archive.ubuntu.com` to download the latest kernel updates during installation. If the VirtualBox bridged network adapter experiences IPv6 blackholing, or the mirror is unresponsive, `apt-get` can hang indefinitely without timing out, permanently freezing the headless installation.

**Resolution:**
To enforce a deterministic, offline build that completely ignores internet mirrors during the installation phase, we configure `cloud-init` to disable updates. 
This block must be present in `user-data`:
```yaml
  apt:
    disable_suites: [updates, security]
```
*(You can safely run `apt update && apt upgrade` via SSH after the machine boots normally.)*

---

## 5. Invalid / Dummy Password Hash

**Symptoms:**
- The VM successfully installs and boots to the `login:` prompt.
- Entering the correct username and password repeatedly results in `Login incorrect`.
- SSH access is similarly denied due to authentication failure.

**Root Cause:**
`cloud-init` requires passwords to be provided as SHA-512 cryptographic hashes in the `user-data` file. If a dummy hash (or a hash that corresponds to a different password) is mistakenly injected into `user-data`, `cloud-init` will faithfully write that invalid hash to the VM's `/etc/shadow` file during installation. Once the VM boots, you will be permanently locked out.

**Resolution:**
Generate a mathematically valid SHA-512 crypt hash for your desired password and inject it into the `user-data` identity block. On Linux systems, this can be generated via `mkpasswd -m sha-512`. On Windows, you can use Python with the `passlib` module. Once corrected, you must re-provision and reinstall the VM to apply the new hash.

---

## 6. Blind Hypervisor / Missing IP Address

**Symptoms:**
- The `04-connect-node.ps1` script fails to retrieve the VM's IP address, eventually timing out after 20 retries.
- The script states: `Could not retrieve IP address. Ensure the VM has finished the OS installation and has rebooted.`

**Root Cause:**
The connection script uses `VBoxManage guestproperty get` to query the IP address from the guest operating system. However, this feature relies entirely on the `virtualbox-guest-utils` daemon running inside the VM. Because we configured a strictly offline installation (disabling APT network updates to avoid the IPv6 hang), the VirtualBox guest additions package was never downloaded or installed.

**Resolution:**
The VM is fully operational and connected to the bridged network; it just cannot report its IP address back to the Windows host. To retrieve the IP address, simply log into the VM's console directly through the VirtualBox Manager GUI and read the IP address from the Ubuntu Welcome Message (MOTD) or run `ip a`. Alternatively, you can explicitly instruct `cloud-init` to install `virtualbox-guest-utils` in the `packages:` block (if network updates are permitted).

---

## 7. Dial-up Speeds / Wi-Fi Bridging Packet Drop

**Symptoms:**
- The VM installs successfully, but `apt-get` downloads (or Docker image pulls) crawl at dial-up speeds.
- Pinging the VM shows severe packet loss.

**Root Cause:**
VirtualBox Bridged Networking has a fatal flaw when bridged over modern Wi-Fi adapters (such as Intel Wi-Fi 6 cards). Because a single Wi-Fi station association generally does not allow multiple MAC addresses, VirtualBox employs a MAC-translation workaround that frequently causes massive packet drops. The default `Intel PRO/1000 MT` network emulation exacerbates this.

**Resolution:**
The architecture was migrated entirely to **NAT**. The VM now securely shares the host's internet connection natively with zero packet drops. The `virtio` paravirtualized network driver was also applied (`--nictype1 virtio`) to maximize throughput. Host access is handled seamlessly via VirtualBox Port Forwarding.

---

## 8. Missing `ssh.exe` on 64-bit Windows

**Symptoms:**
- The deployment scripts fail with `CommandNotFoundException` for `C:\Windows\System32\OpenSSH\ssh.exe`, even though OpenSSH is installed and the file physically exists on the disk.

**Root Cause:**
If you run the scripts from a 32-bit PowerShell process (such as a 32-bit VS Code terminal) on a 64-bit Windows installation, Windows aggressively engages the "File System Redirector". Any attempt to execute a binary in `C:\Windows\System32` is silently redirected to `C:\Windows\SysWOW64`. Because OpenSSH does not ship a 32-bit binary in `SysWOW64`, PowerShell reports that the file does not exist.

**Resolution:**
The deployment scripts implement a dynamic path fallback. They first check for the existence of `$env:WINDIR\sysnative\OpenSSH\ssh.exe` (a virtual alias that forces 32-bit applications to access the true 64-bit `System32` folder) before falling back to the standard path.

---

## 9. Background Installations Failing Silently

**Symptoms:**
- Tailscale or Docker fails to install, but the PowerShell orchestration script reports `[OK] Monitoring Stack Deployed!` without throwing any visible errors.

**Root Cause:**
When PowerShell automates SSH commands that include `sudo` (e.g., `ssh user@ip "sudo apt-get install docker"`), the Linux server cannot interactively prompt you for the `sysadmin` password because the SSH session was not allocated a terminal. `sudo` simply crashes silently in the background, terminating the installation.

**Resolution:**
The `-t` flag (pseudo-TTY) was added to all SSH commands in scripts `05` and `06`. This forces OpenSSH to allocate a true terminal over the network, allowing the Linux `sudo` binary to securely pass its interactive password prompt back to your Windows PowerShell window.

---

## 10. Locked Out After Switching to SSH Key Auth

**Symptoms:**
- `ssh -p 2222 sysadmin@127.0.0.1` hangs or is rejected after a fresh install.
- `03-autoinstall-node.ps1` either failed before completing, or completed but the injected key doesn't match the one on your machine (e.g. you ran it once, generated a key, then deleted `~/.ssh` before a second run).

**Root Cause:**
`user-data` sets `allow-pw: false`, so SSH password authentication is disabled entirely — the VM only accepts the public key that was rendered into `user-data` at install time (`03-autoinstall-node.ps1` reads `~/.ssh/id_ed25519.pub` or `id_rsa.pub`, generating one if neither exists, and writes it into a throwaway copy under `$LabDir`, never into the tracked template). If that key is later regenerated, moved, or the render step silently used a stale/empty value, SSH access breaks.

**Resolution:**
This only disables *SSH* password login — the account password (`sysadmin`, see the `identity` block in `user-data`) still works for a **local console login**, since that's unaffected by the SSH daemon setting:
1. Open the VM directly in the VirtualBox GUI (not headless) and log in at the console with `sysadmin` / the password documented in `user-data`.
2. From the console, fix `~/.ssh/authorized_keys` manually, or re-run `03-autoinstall-node.ps1` (which will re-provision with your current public key) to reinstall cleanly.

The script also fails loudly (`exit 1`) before writing `user-data` at all if it can't read back a well-formed `ssh-...` public key, specifically to avoid ever shipping a VM with authorized-keys empty and SSH password auth disabled.

---

## Conclusion
SysOps automation relies heavily on environmental consistency. When debugging headless installations, always rule out physical file corruption (like the truncated ISO) before tearing apart your bootloader configurations!
