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
| Remote access | Tailscale | ✅ Unattended with a pre-authorised key |
| CI | GitHub Actions | ⚠️ Static validation only — R3 |

---

## Planned

| # | Item | Why | Blocked on |
|---|---|---|---|
| **R1** | Pass `autoinstall` on the kernel command line | Stage 03 clears Subiquity's disk prompt with a 90 s sleep and a blind keystroke. On a slow disk it types into the void | Rebuilding the ISO with a patched `grub.cfg` — needs `xorriso` or ADK `oscdimg` |
| **R2** | Move credentials to `ansible-vault` | The Grafana password and Tailscale key are plaintext on the control node | — |
| **R3** | Test convergence in CI | CI never connects to a node, so a green check cannot show the playbook works | A runner with nested virtualization |
| **R4** | Route alerts through Alertmanager | Rules are evaluated and visible at `:9090/alerts`, but nothing is notified. Alerting nobody is not alerting | — |

---

## Not planned

| Item | Why not |
|---|---|
| Terraform against VirtualBox | Unreliable community provider, and no API to manage — just files and a CLI |
| Rewriting stages 01–03 | They drive `VBoxManage`, `diskpart`, `bcdedit`. A rewrite deletes the interesting part |
| Replacing cloud-init | It is already the declarative OS-install layer, and it works |
| Kubernetes | One node does not motivate an orchestrator |
| Automating Tailscale device approval | Which devices join a tailnet is the operator's decision, not a script's |
