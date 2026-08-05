# Roadmap

A tracker: what is built, what is next, what is deliberately not being built.

Completed work is described in [CHANGELOG.md](CHANGELOG.md). This file says where things stand.

---

## Built

| Layer | Tool | Status |
|---|---|---|
| Host preparation | PowerShell | ✅ Hypervisor conflicts resolved, VirtualBox installed, ISO fetched |
| VM provisioning | PowerShell + `VBoxManage` | ✅ NAT with `virtio`, port-forwards, storage, media |
| OS installation | cloud-init / Subiquity | ⚠️ Works, with one known race — see R1 |
| Connectivity | PowerShell | ✅ Boots the node, polls the forwarded SSH port |
| Configuration | Ansible (from WSL) | ✅ Three roles, `changed=0` on a second run |
| Observability | Prometheus / Grafana / node_exporter | ✅ Verified scraping the VM, not the container |
| Remote access | Tailscale | ✅ Unattended enrolment with a pre-authorised key |
| CI | GitHub Actions | ⚠️ Static validation only — see R3 |

---

## Planned

| # | Item | Why | Status |
|---|---|---|---|
| **R1** | Pass `autoinstall` on the kernel command line | Stage 03 clears Subiquity's disk prompt with a 90 s sleep and a blind keystroke. On a slow disk it types into the void and the install never finishes | Open — blocked on tooling |
| **R2** | Move credentials to `ansible-vault` | The Grafana password and Tailscale key sit as plaintext files on the control node. Fine for a lab, not a pattern to carry forward | Open |
| **R3** | Prove convergence in CI, not just syntax | CI never connects to a node, so a green check cannot show the playbook works | Open — needs a runner with nested virtualization |

### R1 notes

The fix eliminates the prompt rather than timing it: `autoinstall` on the kernel command line makes Subiquity treat the run as fully automated. That means rebuilding the Ubuntu ISO with a patched `boot/grub/grub.cfg`, which needs `xorriso` or the Windows ADK's `oscdimg`.

Two routes:

- **`xorriso` in a container.** Derive the rebuild arguments from `xorriso -indev <iso> -report_el_torito as_mkisofs` rather than guessing, and preserve the volume label exactly — GRUB and casper find the squashfs by label, and a renamed ISO drops to an initramfs prompt.
- **Windows' IMAPI2 COM API.** No third-party tooling, and a better story for a Windows-native pipeline. The VM is BIOS-only, so one no-emulation El Torito entry is enough. Budget real debugging time.

Prove the mechanism with the first before attempting the second.

Until then the race is bounded by a 20-minute deadline rather than hanging, stated in the script header, and documented in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Not planned

Scoping decisions are part of the design. These are declined on purpose.

| Item | Why not |
|---|---|
| **Terraform against VirtualBox** | The provider is community-maintained and unreliable, and there is no API to manage — just local files and a CLI. Terraform belongs against a cloud or Proxmox, where state is a real problem |
| **Rewriting stages 01–03** in Python or Go | They drive `VBoxManage`, `diskpart`, `bcdedit` and DISM. A rewrite reinvents the wheel and deletes the most interesting engineering here |
| **Replacing cloud-init** | It is already the declarative OS-install layer, and it works |
| **Kubernetes** | One node does not motivate an orchestrator. Adding one would be resume-driven development |
| **Fully automating Tailscale device approval** | Which devices join a tailnet is an operator decision, not something a provisioning script should do silently |

---

## Why provisioning and configuration are separate

Stages 01–04 create a machine on a Windows host — `VBoxManage`, `diskpart`, `bcdedit`. That is PowerShell's job, because it is driving Windows-native tooling. Everything afterwards configures a Linux node that is already running, which is Ansible's.

The split is by tool boundary, not file numbering: stage 04 runs `VBoxManage` and stays PowerShell even though it comes last in the provisioning sequence.

The migration was not about the tool's reputation. The same defect — a native command failing while PowerShell carried on to print a success banner — was fixed by hand in four separate scripts. A convention repeated four times is an argument for making it structural. In Ansible, a play halts at the failing task and names it.

What it did **not** buy, stated plainly: not scale (there is one node), not speed, not capability. Ansible also does not repair `dpkg` for free — that step survives as an explicit task, it just gained a condition and an honest exit status.
