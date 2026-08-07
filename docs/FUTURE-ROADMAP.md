# Roadmap

What is built, what is next, what is deliberately not being built. History lives in [CHANGELOG.md](CHANGELOG.md).

---

## Built

| Layer | Tool | Status |
|---|---|---|
| Host preparation | PowerShell | ✅ |
| VM provisioning | PowerShell + `VBoxManage` | ✅ NAT, `virtio`, port-forwards |
| OS installation | cloud-init / Subiquity | ⚠️ Works, one known race — R1 |
| Connectivity | PowerShell | ✅ |
| Configuration | Ansible (from WSL) | ✅ Three roles, `changed=0` on a second run |
| Observability | Prometheus / Grafana / node_exporter | ✅ Verified scraping the VM, not the container |
| Alerting | Prometheus rules / Alertmanager | ✅ Five rules, grouped and routed to Discord, each linked to a runbook and unit-tested with `promtool test rules` |
| Remote access | Tailscale | ✅ Unattended with a pre-authorised key |
| CI | GitHub Actions | ⚠️ Five jobs. The rules are behaviour-tested; the pipeline itself is not — R3 |

---

## Planned

| # | Item | Why | Blocked on |
|---|---|---|---|
| **R1** | Pass `autoinstall` on the kernel command line | Stage 03 clears Subiquity's disk prompt with a 90 s sleep and a blind keystroke. On a slow disk it types into the void | Rebuilding the ISO with a patched `grub.cfg` — needs `xorriso` or ADK `oscdimg` |
| **R2** | Move credentials to `ansible-vault` | The Grafana password and Tailscale key are plaintext on the control node | — |
| **R3** | Test convergence in CI, against a QEMU guest | CI never connects to a node, so a green check cannot show the playbook converges | Nothing external. GitHub's Linux runners expose `/dev/kvm`, so nested virtualisation is no longer the obstacle it was when this was written. VirtualBox still cannot run there, so the test would boot an Ubuntu cloud image under QEMU and run `site.yml` against it twice. That covers the Ansible half only — stages 01-04 drive Windows tooling and stay verified by hand |

---

## Not planned

| Item | Why not |
|---|---|
| Terraform against VirtualBox | Unreliable community provider, and no API to manage — just files and a CLI |
| Rewriting stages 01–03 | They drive `VBoxManage`, `diskpart`, `bcdedit`. A rewrite deletes the interesting part |
| Replacing cloud-init | It is already the declarative OS-install layer, and it works |
| Kubernetes | One node does not motivate an orchestrator |
| Automating Tailscale device approval | Which devices join a tailnet is the operator's decision, not a script's |
