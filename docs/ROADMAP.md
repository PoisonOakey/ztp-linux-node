# Roadmap

What is built, what is planned, and what is deliberately not being built. Kept honest — anything listed as done is verified by an end-to-end run, and anything incomplete says so.

---

## Current state

| Layer | Tool | Status |
|---|---|---|
| Host preparation | PowerShell | Done — hypervisor conflicts resolved, VirtualBox installed, ISO fetched |
| VM provisioning | PowerShell + `VBoxManage` | Done — NAT with `virtio`, port-forwards, storage, media mounted |
| OS installation | cloud-init / Subiquity | Done, with one known limitation (see below) |
| Connectivity | PowerShell | Done — boots the node, polls the forwarded SSH port |
| Configuration management | PowerShell over SSH | **Working, but hand-rolled — the target of the next phase** |
| Observability | Docker / Prometheus / Grafana / node_exporter | Done — verified scraping the VM, not the container |
| CI | GitHub Actions | Static validation only: `PSScriptAnalyzer`, config schema check, `docker compose config` |

---

## Planned: move configuration management to Ansible

### Rationale

Provisioning and configuration are separate concerns, and this repository currently blurs them.

Stages 01–04 provision a machine on a Windows host — creating a VM, driving `diskpart`, mounting media, booting it. That is legitimately PowerShell's job and it stays.

Stages 05 and 06 configure a Linux node that is already running: `apt-get install`, `systemctl enable --now`, `docker compose up -d`, plus a hand-written idempotency guard (`dpkg --configure -a || true`). That is Ansible's core competency, currently reimplemented by hand.

This is not a rewrite for its own sake. It removes real code — `sysnative` path resolution for `ssh.exe`/`scp.exe`, heredocs piped over SSH, a hardcoded address in three files — and replaces imperative steps with declarative desired state.

### The concrete problem it solves

The architectural argument above is the tidy one. The specific defect is more useful.

**Failure reporting.** `$ErrorActionPreference = 'Stop'` does not apply to native executables. A failing `ssh.exe` or `VBoxManage.exe` only sets `$LASTEXITCODE`, and PowerShell continues to the next line — so any stage that ran a command and then printed a banner reported success over work that never happened. Stage 06 was the worst case: its payload is a six-command `&&` chain, so a failure gave no indication which of the six died.

This defect appeared independently in four scripts and has now been fixed by hand in all four — `02`, `03`, `05` and `06` each carry their own `$LASTEXITCODE` guard. **That repetition is the argument.** The fix is correct but it is a convention, and a convention is only as reliable as the next person remembering it. In Ansible, per-task failure reporting is not something you add — a play halts at the failing task and names it. The bug becomes unconstructable rather than merely absent.

See `TROUBLESHOOTING.md` #9 and #14 for the two occurrences that were diagnosed from live failures rather than found by reading.

**Idempotency is currently accidental.** `apt-get install -y` and `docker compose up -d` happen to be safe to re-run. `scp -r` is not — it re-copies the whole directory every time regardless of whether anything changed. Nothing in the current pipeline can report whether a second run changed anything. Ansible's `ok`/`changed` accounting makes that a property you can verify rather than one you assume.

**Quoting layers.** The configuration steps are a bash script embedded in a PowerShell here-string, executed over SSH with a pseudo-TTY. Three levels of quoting, where an escaping error surfaces only at runtime on the far side of a network connection. Ansible modules take structured arguments and there is no shell to quote for.

### What this does not solve

Stated plainly, because overclaiming here would be worse than not doing it at all:

- **Not scale.** There is one node. The fleet-management argument does not apply.
- **Not speed.** It will be marginally slower than raw SSH.
- **Not capability.** It adds nothing the current pipeline cannot already do.

The value is entirely in failure semantics, provable idempotency, and the separation of concerns — not in the tool's reputation.

### Scope

Stages **05 and 06 only**. Stage 04 stays PowerShell: it runs `VBoxManage startvm` and polls a TCP port, which is provisioning, not configuration. Splitting on the tool boundary rather than the file numbering is the point of the exercise.

```
ansible/
├── ansible.cfg            explicit remote_user, host key checking off for the lab
├── inventory.ini          node at 127.0.0.1:2222, user sysadmin, key-based
├── site.yml               top-level play
└── roles/
    ├── docker/            install docker.io + docker-compose-v2, enable the service
    ├── tailscale/         install, run `tailscale up`, surface the auth URL
    └── monitoring/        template .env, copy monitoring/, bring the stack up
```

`config/node.json` stays exactly as it is. It serves the PowerShell provisioning stages and describes hardware that exists before the OS does; Ansible gets its own inventory. Merging them would destroy the boundary this change exists to draw.

### Requirements

1. **The generated Grafana password must survive the port.** It is currently generated once and written to `monitoring/.env`. A naive port regenerates it on every run, which both rotates the password unexpectedly and breaks idempotency. Use a persisted lookup. Never commit the value.
2. **The Compose file is copied as-is.** `node_exporter`'s `/proc`, `/sys`, `/rootfs` bind mounts and matching `--path.*` flags are load-bearing — without them it reports the container's metrics instead of the VM's, silently and plausibly.
3. **`tailscale up` prints an interactive authentication URL** that a human clicks once. This will not be fully automated. Surface the URL clearly and document the manual step.
4. **Idempotency is the acceptance test.** Running `site.yml` twice must report zero changes on the second run.
5. **`Deploy-Node.ps1` remains the single entrypoint.** After stage 04 it invokes `ansible-playbook` through WSL. If Ansible is unavailable it must fail with an actionable message — never silently skip. A "pipeline complete" banner over work that did not run is a defect this project has already been burned by once.
6. **The replaced scripts are deleted in the same change that adds the roles.** A `tailscale` role sitting beside `05-setup-tailscale.ps1` is worse than either alone, because nothing tells a reader which one runs.
7. **Extend CI** with `ansible-lint` and `ansible-playbook --syntax-check`. Note honestly that this is still static validation — it does not prove the playbook converges.

### Prerequisites

Control node setup is documented separately in [ANSIBLE-SETUP.md](ANSIBLE-SETUP.md). It is a one-time WSL 1 install and is already verified working against this VM.

---

## Deferred: eliminate the Stage 03 timing race

`03-autoinstall-node.ps1` clears Subiquity's destructive-disk confirmation by waiting a fixed 90 seconds and then injecting a keystroke. Nothing verifies the prompt is actually on screen. On a slow disk the keystroke goes nowhere and the installation never completes.

The correct fix is to pass `autoinstall` on the kernel command line, which makes Subiquity treat the run as fully automated and skip the confirmation entirely. That requires rebuilding the Ubuntu ISO with a patched `boot/grub/grub.cfg`, which needs `xorriso` or the Windows ADK's `oscdimg` — neither currently available on the build host.

Two viable approaches when this is picked up:

- **`xorriso` in a container.** Derive the rebuild arguments from `xorriso -indev <iso> -report_el_torito as_mkisofs` rather than guessing them, and preserve the volume label exactly — GRUB and casper locate the squashfs by label, and a renamed ISO drops to an initramfs prompt.
- **Windows' built-in IMAPI2 COM API.** No third-party tooling. The VM is BIOS-only, so a single no-emulation El Torito entry from `boot/grub/i386-pc/eltorito.img` is sufficient. A better story for a Windows-native pipeline, but budget real debugging time.

Prove the mechanism with the first before considering the second.

Until then the limitation is stated in the script header, the installation is bounded by a 20-minute deadline in the orchestrator rather than hanging indefinitely, and the failure mode is documented in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Explicit non-goals

Things deliberately not being built, and why. Scoping decisions are as much a part of the design as the code.

- **Terraform against VirtualBox.** The provider is community-maintained and unreliable. There is also no API here for Terraform to manage — the resources are local files and a `VBoxManage` CLI. If Terraform belongs anywhere, it is a separate project against a cloud API or Proxmox, where state management is a real problem rather than an affectation.
- **Rewriting stages 01–03 in Python, Go, or anything else.** They drive Windows-native tooling: `VBoxManage`, `diskpart`, `bcdedit`, DISM. A rewrite reinvents the wheel and deletes the most interesting engineering in the repository.
- **Replacing cloud-init.** It is already the declarative OS-installation layer, and it works.
- **Kubernetes.** A single-node homelab does not motivate an orchestrator. Adding one would be resume-driven development, not engineering.
- **Fully automating Tailscale device approval.** Which devices join a tailnet is an operator decision, not something a provisioning script should do silently. The one-time browser approval stays manual and documented.
