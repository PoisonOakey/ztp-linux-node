# Ansible Control Node Setup (Windows Host)

This document covers the one-time setup required to run Ansible against the provisioned node from a Windows host. It is a prerequisite for the configuration-management migration described in [ROADMAP.md](ROADMAP.md).

Ansible has no native Windows control node — it must run from a POSIX environment. On this project that environment is **WSL 1**, and the choice of 1 over 2 is not incidental. See below.

---

## Why WSL 1, not WSL 2

This is the single most important decision in this document, and getting it wrong costs an evening.

**WSL 2 directly conflicts with this project's own host preparation.** `scripts/01-host-prep.ps1` deliberately disables three Windows features so VirtualBox gets exclusive access to the CPU's virtualization extensions:

```powershell
$features = @("Microsoft-Hyper-V-All", "HypervisorPlatform", "VirtualMachinePlatform")
```

WSL 2 is a virtual machine. It requires `VirtualMachinePlatform` and the Windows hypervisor — precisely what stage 01 turns off. Install WSL 2 and the two fight permanently: run `Deploy-Node.ps1` and it disables the feature and demands a reboot, breaking WSL; re-enable it for Ansible and VirtualBox loses raw VT-x. There is no stable resting state.

**WSL 1 is a syscall translation layer, not a VM.** It needs no hypervisor and no `VirtualMachinePlatform`, so it coexists with VirtualBox at full speed.

For this specific workload WSL 1 is also *better*, not merely a workaround:

| | WSL 1 | WSL 2 |
|---|---|---|
| Needs `VirtualMachinePlatform` | No | Yes — conflicts with stage 01 |
| `127.0.0.1` from inside | Windows loopback, shared network stack | Separate NAT'd adapter — a *different* machine |
| Reaching the VM's port-forward | Works directly | Requires the host's LAN IP or mirrored networking |

That second row matters more than it looks. The node is reached at `127.0.0.1:2222` via a VirtualBox NAT port-forward listening on the Windows loopback. From WSL 1 that is the same loopback. From WSL 2, `127.0.0.1` is the WSL VM itself, and the connection fails in a way that is tedious to diagnose.

WSL 1's weakness is filesystem and syscall throughput. Ansible is Python and SSH, so this is irrelevant here.

### Trade-off you are accepting

**Docker Desktop will not run while `VirtualMachinePlatform` is disabled**, because its backing distro is WSL 2. This is a pre-existing tension on any host running both Docker Desktop and VirtualBox — it is not introduced by Ansible.

It does not affect this pipeline. The monitoring stack runs in Docker *inside the VM*, not on the Windows host. Docker Desktop is only needed if you want containers on Windows itself.

---

## Setup

Commands are labelled by which shell they run in. Mixing these up is the most common source of confusion — `sudo` and `apt` are Linux, `wsl` and `VBoxManage` are Windows.

### 1. Install WSL 1 with Ubuntu

**PowerShell (Administrator):**

```powershell
wsl --set-default-version 1
wsl --install -d Ubuntu
wsl --set-default Ubuntu
```

`--set-default-version 1` must come first, or the distro is created as WSL 2 and has to be converted with `wsl --set-version Ubuntu 1`.

The last line matters: if another WSL 2 distro is installed (Docker Desktop registers one), a bare `wsl` launches *that* instead and fails with `HCS_E_HYPERV_NOT_INSTALLED`.

**Verify — Ubuntu:**

```bash
uname -r
```

Expect a kernel like `4.4.0-26100-Microsoft`. If it ends in `-microsoft-standard-WSL2`, you are on WSL 2 and must convert.

> **Expect one extra reboot here.** `wsl --install` enables `VirtualMachinePlatform` and sets `hypervisorlaunchtype` to `Auto` regardless of which WSL version you end up on. `01-host-prep.ps1` disables both so VirtualBox gets direct access to the CPU's virtualization extensions, so the next pipeline run will detect the change, re-apply it, and require a restart. This happens once. With WSL 1 it does not recur, because WSL 1 needs no hypervisor. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) #16.

### 2. Fix DNS

WSL 1 generates `/etc/resolv.conf` from the Windows network configuration. If a VPN client manages DNS on the host — Tailscale, in this project's case — Windows reports placeholder addresses that WSL cannot use:

```
nameserver fec0:0:0:ffff::1
search <tailnet>.ts.net
```

Name resolution fails while raw IP connectivity works fine (`ping 1.1.1.1` succeeds). Pin a resolver instead.

**Ubuntu:**

```bash
printf '[network]\ngenerateResolvConf = false\n' | sudo tee /etc/wsl.conf
```

**PowerShell:**

```powershell
wsl --shutdown
```

**Ubuntu (after relaunching):**

```bash
sudo rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee /etc/resolv.conf
getent hosts archive.ubuntu.com
```

The `rm` must happen *after* the restart — the original is a symlink into `/run`, and WSL only stops managing it once `wsl.conf` has been read on a fresh boot.

This pins DNS permanently. If you later need an internal resolver, edit `/etc/resolv.conf` directly.

### 3. Force APT over IPv4

`archive.ubuntu.com` resolves to IPv6 addresses first. If IPv6 is blackholed on the path, `apt` hangs indefinitely rather than falling back — the same failure documented in [TROUBLESHOOTING.md](TROUBLESHOOTING.md) #4 for the installer.

**Ubuntu:**

```bash
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4
sudo apt update
```

### 4. Install Ansible

**Ubuntu:**

```bash
sudo apt install -y ansible
ansible --version
```

### 5. Make the SSH key usable

`03-autoinstall-node.ps1` injects the host's public key into the VM at install time. Ansible needs the matching private key — but Windows files under `/mnt/c` report mode `0777`, and OpenSSH refuses a world-readable private key. `chmod` on `/mnt/c` does not persist by default.

Copy it into the WSL filesystem instead.

**Ubuntu:**

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cp /mnt/c/Users/<you>/.ssh/id_ed25519 ~/.ssh/
chmod 600 ~/.ssh/id_ed25519
ls -l ~/.ssh/id_ed25519
```

Expect `-rw-------`.

> This copy is a second location holding private key material. It lives in the WSL filesystem, outside the repository, and is never committed. If you rebuild the WSL distro, repeat this step.

---

## Verify the control node

With the VM running (`.\scripts\04-connect-node.ps1` from PowerShell):

**Ubuntu:**

```bash
ANSIBLE_HOST_KEY_CHECKING=False ansible all -i '127.0.0.1:2222,' \
  -u sysadmin --private-key ~/.ssh/id_ed25519 -m ping
```

Success:

```json
127.0.0.1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

This single command proves every dependency at once: WSL reaches the VirtualBox port-forward, key authentication works end to end, and Python is present on the managed node. If it returns `pong`, nothing environmental stands between you and running playbooks.

Add `-vvv` to any failing invocation — it dumps the full SSH negotiation and usually names the cause outright.

### Expected interpreter warning

Ansible warns that it discovered `/usr/bin/python3.12` and a future install could change that. It is harmless, and pinning `ansible_python_interpreter=/usr/bin/python3` in the inventory silences it.

---

## Running playbooks: `ANSIBLE_CONFIG` is not optional

Ansible refuses to load an `ansible.cfg` from a world-writable directory, on the reasoning that anyone able to write there could hijack the run. Everything under `/mnt/d` reports mode `0777` to Linux, so the repository's `ansible.cfg` is ignored by the normal current-directory discovery:

```
[WARNING]: Ansible is being run in a world writable directory
(/mnt/d/ztp-homelab/ansible), ignoring it as an ansible.cfg source.
```

The failure that follows is misleading rather than obvious — the inventory is never parsed, so the play reports `skipping: no hosts matched` as though the inventory were wrong.

Point at the config file explicitly instead:

```bash
cd /mnt/d/ztp-homelab/ansible
ANSIBLE_CONFIG=$PWD/ansible.cfg ansible-playbook site.yml
```

An explicitly named config is honoured regardless of directory permissions.

This is the same root cause as the private key needing a copy into `~/.ssh`: Windows filesystems mounted into WSL cannot express Unix permissions, and tools that check permissions for security reasons reject them. It is worth recognising the shape, because it will keep recurring with any tool that validates file modes.

### Permanent alternative

Mounting the Windows drives with real permission metadata fixes the whole class at once, at the cost of a restart and one privileged edit. Add to `/etc/wsl.conf`:

```ini
[automount]
options = "metadata,umask=022,fmask=011"
```

Then `wsl --shutdown` from PowerShell and relaunch. Files under `/mnt/*` will report `0644` and directories `0755`, and `ansible.cfg` is picked up without the environment variable.

The explicit `ANSIBLE_CONFIG` approach is preferred in this repository because it works on any machine without host-level configuration, which matters more for something another person might clone.

---

## Persistence

All of the above survives reboots. `wsl.conf`, the pinned resolver, the APT configuration, and the copied key are all on the WSL filesystem. This is a one-time setup, not a per-session ritual.

The only step that repeats is booting the VM before a playbook run.
