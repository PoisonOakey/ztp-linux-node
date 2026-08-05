# Ansible Control Node Setup (Windows)

Ansible needs a Linux control node. On Windows that means WSL. This is a one-time setup.

> [!IMPORTANT]
> Use **WSL 1**, not WSL 2. WSL 2 is a virtual machine and needs the Windows hypervisor — which `01-host-prep.ps1` disables so VirtualBox gets the CPU's virtualization extensions. Install WSL 2 and the two fight on every run.

WSL 1 is also the better fit here: it shares the Windows network stack, so `127.0.0.1:2222` reaches the VirtualBox port-forward. From WSL 2 that address is a different machine entirely.

Commands below are labelled by shell. `sudo` and `apt` are Linux. `wsl` and `VBoxManage` are Windows.

---

## 1. Install WSL 1

**PowerShell (Administrator):**

```powershell
wsl --set-default-version 1
wsl --install -d Ubuntu
wsl --set-default Ubuntu
```

Order matters. Set version 1 first, or the distro is created as WSL 2 and needs converting with `wsl --set-version Ubuntu 1`.

The last line matters too: Docker Desktop registers its own WSL 2 distro, and if that stays the default, a bare `wsl` starts it and fails with `HCS_E_HYPERV_NOT_INSTALLED`.

**Ubuntu:**

```bash
uname -r
```

Expect `4.4.0-...-Microsoft`. Anything ending `-microsoft-standard-WSL2` is WSL 2 — convert it.

> [!NOTE]
> `wsl --install` re-enables the Windows hypervisor, so your next pipeline run will disable it again and ask for a reboot. This happens once. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) #16.

---

## 2. Fix DNS

WSL 1 copies its DNS settings from Windows. If a VPN client manages DNS on the host, WSL inherits unusable placeholder addresses — name resolution fails while `ping 1.1.1.1` still works.

**Ubuntu:**

```bash
printf '[network]\ngenerateResolvConf = false\n' | sudo tee /etc/wsl.conf
```

**PowerShell:**

```powershell
wsl --shutdown
```

**Ubuntu** (after relaunching — the restart is required before this step):

```bash
sudo rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee /etc/resolv.conf
getent hosts archive.ubuntu.com
```

---

## 3. Install Ansible

`archive.ubuntu.com` resolves to IPv6 first. If IPv6 is blackholed, `apt` hangs instead of falling back.

**Ubuntu:**

```bash
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4
sudo apt update
sudo apt install -y ansible
```

---

## 4. Copy the SSH key

`03-autoinstall-node.ps1` injects your public key into the VM. Ansible needs the private half — but Windows files under `/mnt/c` report mode `0777`, and OpenSSH refuses a world-readable key.

**Ubuntu:**

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cp /mnt/c/Users/<you>/.ssh/id_ed25519 ~/.ssh/
chmod 600 ~/.ssh/id_ed25519
```

---

## Verify

With the VM running (`.\scripts\04-connect-node.ps1`):

**Ubuntu:**

```bash
ANSIBLE_HOST_KEY_CHECKING=False ansible all -i '127.0.0.1:2222,' \
  -u sysadmin --private-key ~/.ssh/id_ed25519 -m ping
```

`"ping": "pong"` proves everything at once: WSL reaches the port-forward, the key works, Python is on the target.

Add `-vvv` to any failure — it dumps the SSH negotiation and usually names the cause.

---

## Running playbooks

```bash
cd /mnt/d/ztp-linux-node/ansible          # wherever you cloned it, under /mnt/<drive>/
ANSIBLE_CONFIG=$PWD/ansible.cfg ansible-playbook site.yml -K
```

> [!IMPORTANT]
> `ANSIBLE_CONFIG` is not optional. Ansible ignores an `ansible.cfg` in a world-writable directory, and `/mnt/d` is `0777`. Leave it off and the inventory is never read — the play reports `no hosts matched`, as though the inventory were at fault.

Same root cause as the SSH key: Windows drives can't express Unix permissions, and tools that check them refuse.

To fix it permanently instead, add `[automount]` with `options = "metadata,umask=022,fmask=011"` to `/etc/wsl.conf` and restart WSL. The environment variable is preferred here because it works on any machine with no host configuration.

---

## Optional: unattended Tailscale

Without a key, a new node needs a human to approve it in a browser. With one, every rebuild joins on its own.

Tailscale admin console → **Settings → Keys → Generate auth key**. Make it **reusable** if you rebuild the VM.

```bash
echo 'tskey-auth-...' > ansible/.tailscale_auth_key    # from the repository root
```

Gitignored, read automatically, never committed. Treat it as a credential and give it an expiry.

---

All of this survives reboots. The only step you repeat is booting the VM before a run.
