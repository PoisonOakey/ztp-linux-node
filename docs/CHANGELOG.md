# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Changed
- **`Deploy-Node.ps1` hands off to Ansible after stage 04.** Provisioning stops once the node is booted and reachable; configuration is a separate concern and now runs as a playbook. The distro is named explicitly rather than relying on the WSL default, because Docker Desktop registers its own WSL 2 distro and a bare `wsl` invocation would start that instead and fail with `HCS_E_HYPERV_NOT_INSTALLED`. Paths are translated with `wslpath` rather than string surgery on the drive letter, so the repository can move. If WSL or Ansible is unavailable the script fails with an actionable message naming `docs/ANSIBLE-SETUP.md` -- it never skips configuration silently.
- **Ansible failures are checked like every other native call.** Verified that both failure modes cross the WSL boundary intact: a missing playbook returns exit 1 and a task-level failure returns exit 2, each tripping the guard. A successful run returns 0.

### Removed
- **`scripts/05-setup-tailscale.ps1` and `scripts/06-setup-monitoring.ps1`**, replaced by the `tailscale` and `monitoring` roles. Deleted in the same change that wires the playbook in, so there is never a state where both implementations exist and nothing tells a reader which one runs.
- Documentation referring to those scripts in the present tense was updated: `TROUBLESHOOTING.md` #8 (the `sysnative` fallback now applies only to `ssh-keygen.exe` in the provisioning stages, since Ansible runs from WSL and uses the Linux SSH client), #9, #13 and #15, plus a comment in `02-provision-node.ps1`.

### Added
- **`monitoring` role:** replaces the `scp` and `docker compose up` half of `06-setup-monitoring.ps1`. Files are listed explicitly rather than copied wholesale, so the control node's `.env.example` no longer ships to the target, and `community.docker.docker_compose_v2` reports whether the stack actually changed instead of always claiming it did. Verified: `changed=4` on first run, `changed=0` on the second, with Grafana and Prometheus both answering `200` and both scrape targets `up` afterwards.
- **Grafana password survives the port (G2):** the password is generated once via the `password` lookup and persisted to `ansible/.grafana_admin_password` on the control node, which is gitignored. Every later run reads the same value. A naive port would regenerate it each run, rotating the credential unexpectedly and breaking idempotency, since the rendered `.env` would differ every time and restart the container. The rendered file is `0600` and both the lookup and the template task are marked `no_log`.
- **`tailscale` role:** replaces `05-setup-tailscale.ps1`. Two changes beyond translation. The install no longer pipes an unverified remote script into a root shell (`curl -fsSL https://tailscale.com/install.sh | sh`) -- Tailscale's signed apt repository is added instead, with the release codename taken from gathered facts rather than hardcoded. And `tailscale up` is no longer run on every deployment: the role reads the node's backend state first and leaves an already-connected node alone. Verified: `ok=15 changed=0 skipped=3` on two consecutive runs, with both authentication paths correctly skipped on a connected node.
- **Optional non-interactive Tailscale auth:** supplying `tailscale_auth_key` joins the tailnet with no human step; the key is passed at run time, never committed, and marked `no_log`. Without one, a disconnected node fails with instructions rather than hanging -- `tailscale up` blocks until a human opens the URL it prints, and Ansible buffers task output until a task completes, so running it inside a play would hang with the URL invisible. This answers the open question of whether device approval should be a manual step or use a pre-authorised key: both are supported, and the default requires no credential.
- **`docker` role:** replaces the apt/systemctl half of `06-setup-monitoring.ps1`. Installs `docker.io` and `docker-compose-v2`, asserts the service is enabled and running, and confirms the daemon responds via `docker info` rather than `docker --version`, which reports only the client and would pass with the service stopped. Verified against the provisioned node: `ok=8 changed=0 skipped=1` on two consecutive runs.
- **Conditional dpkg repair:** the PowerShell original ran `dpkg --configure -a || true` on every deployment, discarding whatever it might have reported. The role checks `dpkg --audit` first and skips the repair on a healthy node. Noted in `ROADMAP.md` that Ansible does *not* provide this for free -- the step is still hand-written, it just gained a condition and an honest exit status.
- **Ansible control-node skeleton (`ansible/`):** `inventory.ini`, `ansible.cfg` and a `site.yml` smoke test, on the `ansible-migration` branch. No roles yet -- this is the wiring only, verified with two consecutive runs reporting `ok=3 changed=0`. Every setting in `ansible.cfg` is confirmed in effect via `ansible-config dump --type all --only-changed`; defaults are deliberately not restated.
- **`docs/ANSIBLE-SETUP.md` -- running playbooks:** Ansible ignores an `ansible.cfg` found in a world-writable directory, and everything under `/mnt/d` reports mode `0777` to WSL. The resulting failure is misleading: the inventory is never parsed, so the play reports `skipping: no hosts matched` as though the inventory were at fault. Documents the explicit `ANSIBLE_CONFIG` invocation and the `wsl.conf` `automount` alternative.

## [1.10.0] - 2026-08-05
### Fixed
- **Stages 05 and 06 reported success over failed runs:** both scripts ran their `ssh`/`scp` payload and then printed their success banner unconditionally. `$ErrorActionPreference = 'Stop'` does not apply to native executables, so a failed Tailscale install or a failed `docker compose up` still produced `[OK] Monitoring Stack Deployed!`. Stage 06's payload is a six-command chain, so a failure also gave no indication which step died. Both now check `$LASTEXITCODE` after every remote call and throw with the exit status. This is the same defect fixed in stages 02 and 03 in 1.9.0 -- the fourth hand-written instance, and a large part of the motivation for the Ansible migration in `ROADMAP.md`.
- **Transcript leak in stages 05 and 06:** neither reached `Stop-Transcript` on a failure path, which the new `throw` statements would have made routine. Both bodies are now wrapped in `try/finally`, matching stage 03.
- **Missing `.env.example` failed silently:** `06-setup-monitoring.ps1` read the template without checking it existed. On a repository missing it, `Get-Content` returned nothing and the generated `monitoring/.env` was empty, deploying Grafana on its `admin/admin` default -- the exact outcome the generation step exists to prevent. It now throws instead.

### Added
- **`docs/ROADMAP.md`:** current state of each layer, the planned move of configuration management to Ansible with its scope and requirements, the deferred stage 03 ISO patch, and explicit non-goals with reasoning.
- **`docs/ANSIBLE-SETUP.md`:** one-time control-node setup on Windows. Documents why WSL **1** is required rather than WSL 2 -- WSL 2 needs `VirtualMachinePlatform`, which `01-host-prep.ps1` disables so VirtualBox gets raw VT-x, and the two cannot coexist. Also covers the DNS failure caused by a VPN client managing host DNS, forcing APT over IPv4, and the private-key permission workaround for files under `/mnt/c`. Verified end to end against the provisioned node.

## [1.9.0] - 2026-08-05
### Fixed
- **Install wait-loop could hang forever:** `Deploy-Node.ps1`'s `while ($isInstalling)` loop polled `VBoxManage showvminfo` every 15s with no deadline and no escape, so a stalled install blocked the orchestrator indefinitely with no diagnostic. Added a parameterized deadline (`-InstallTimeoutMinutes`, default 20) and an explicit throw when `showvminfo` stops returning a state at all (VM deleted, or VirtualBox unreachable). Both errors name the VM and the transcript path.
- **Orchestrator had no transcript:** `Deploy-Node.ps1` was the only script without `Start-Transcript`, so the one file a failed run should point you at did not exist. Added it, with `Stop-Transcript` in a `finally` so it closes on the error paths too.
- **Dangling VHD on failure:** `03-autoinstall-node.ps1` mounted a FAT32 VHD and assigned it a drive letter under `$ErrorActionPreference = 'Stop'` with no `try/finally`, so any failure between `attach vdisk` and `detach vdisk` left a mounted volume holding a live drive letter alongside a half-built VM. Wrapped the mount/inject/unmount sequence and moved the detach into `finally`. The `finally` suppresses its own errors so cleanup can never mask the original exception. The pre-existing next-run cleanup is kept as a second layer.
- **Stage 03 could only ever run once:** `03-autoinstall-node.ps1` rebuilds `cidata.vhd` from scratch on every run, so the new file gets a new UUID while VirtualBox's media registry (`VirtualBox.xml`) still holds the previous one and the VM still has it attached at SATA port 1. Every run after the first died with `UUID ... does not match the value stored in the media registry` and left the VM unbootable. The script now detaches the medium and closes the stale registry entry before recreating the disk, looking the entry up by location and closing it by UUID -- closing by path makes VirtualBox reopen the file and re-run the very UUID comparison that is already failing.
- **Stage 03 reported success on a failed run:** `$ErrorActionPreference = 'Stop'` does not apply to native executables, so a failing `VBoxManage` call only set `$LASTEXITCODE` and execution continued. When the medium-registry error above aborted `startvm`, the script still slept 90 seconds, still fired `keyboardputstring` at a VM that was not running, and still printed "Automated installation has been triggered!". Added explicit `$LASTEXITCODE` checks after the `storageattach` and `startvm` calls so the run fails loudly at the point of failure.
- **`2>$null` on `VBoxManage` aborted runs instead of silencing them:** several stages suppressed expected `VBoxManage` failures (closing an unregistered medium, detaching an empty slot) with `2>$null`. In PowerShell 5.1 redirecting a native command's stderr wraps each line in an `ErrorRecord`, which `$ErrorActionPreference = 'Stop'` then promotes to a terminating error -- so the redirection did the opposite of what it looked like, and turned a tolerable failure into a fatal one. Replaced in `Deploy-Node.ps1`, `02-provision-node.ps1`, and `03-autoinstall-node.ps1` with either an explicit precondition check or a scoped `'Continue'`, so expected failures are tolerated deliberately rather than by redirection.
- **Stage 03 silently did nothing against an already-installed VM:** Subiquity ejects the install media at the end of a successful install, so re-running stage 03 standalone booted the installed OS instead of an installer -- indistinguishable, from the outside, from a hung install. Added a check that an ISO is actually attached to the IDE controller, failing with the same "run Stage 2 first" guidance the missing-VM check already gives.
- **Transcript leak in stage 03:** the script exits via `Write-Error` + `exit 1` in five places and reached `Stop-Transcript` on none of them. Wrapped the body in `try/finally`.
- **Four docstrings described code that does not exist:** `02-provision-node.ps1` claimed it "automatically detects and configures the bridged network adapter" (it configures NAT with `virtio` and three port-forwards); `04-connect-node.ps1` claimed it "queries the VirtualBox Guest Properties to discover the IP address assigned by your local DHCP server" (it polls `127.0.0.1:2222`); `05-setup-tailscale.ps1` and `06-setup-monitoring.ps1` both claimed to query the VM for its IP, and both documented a `.PARAMETER VmName` against an empty `param()`. All corrected to describe the NAT port-forwarding the code actually uses; the two phantom parameters are gone.
- **Dead IP cache:** `04-connect-node.ps1` wrote `$env:TEMP\.sre-node-ip.txt`, which nothing ever read -- its own comment admitted the other scripts hardcode `127.0.0.1`. Removed, along with the variable that fed it.
- **Mojibake in the orchestrator banner:** `Deploy-Node.ps1` printed `ðŸš€` and `ðŸŽ‰` -- emoji bytes double-encoded (UTF-8 read as Latin-1) in a file with no BOM, and the first output a user sees. Replaced with ASCII markers matching the `[OK]` / `[*]` / `[X]` convention the other stages already use, rather than re-encoding: Windows PowerShell 5.1's console host cannot render astral-plane codepoints regardless of file encoding. Emoji in `README.md` and the docs are unaffected and deliberately kept.
- **Obsolete Compose schema key:** removed `version: '3.8'` from `monitoring/docker-compose.yml`, which current Docker Compose warns on. Covered by the existing CI job.
- **Empty cloud-init meta-data:** `scripts/cloud-init/meta-data` was a single newline. Populated with `instance-id` and `local-hostname` matching the `hostname` in `user-data`, which is what the NoCloud datasource conventionally expects.

- **Stale SSH host key on every rebuild:** reinstalling the OS generates a new host key, but the previous node's key stayed pinned in `~/.ssh/known_hosts` against the same `[127.0.0.1]:2222` address, so stages 05 and 06 printed a `REMOTE HOST IDENTIFICATION HAS CHANGED` warning mid-pipeline. `-o StrictHostKeyChecking=no` does not cover this -- it suppresses prompts for *unknown* hosts, never *changed* ones. `02-provision-node.ps1` now runs `ssh-keygen -R "[127.0.0.1]:2222"` right after creating the VM.

### Changed
- **Documentation corrected against the code:** `README.md` claimed zero-touch provisioning "injected `debconf_selections`", which has not been in `user-data` for several releases -- the bootloader prompt is seeded by cloud-init's `grub_dpkg` module. `TROUBLESHOOTING.md` #3 documented the same stale mechanism, and #6 described IP discovery via `VBoxManage guestproperty` over a bridged network, neither of which the project has used since 1.3.0. All three now describe what the code does; #3 and #6 keep their original symptoms so the entries are still findable by the error text.
- **Metrics stated with their conditions:** `README.md`'s provisioning figure was an unsourced "~4 minutes". Replaced with 3 min 53 s to a booted OS and 7 min 35 s for the full pipeline, qualified as a single end-to-end run on a 2 vCPU / 4 GB guest rather than a benchmark. Also dropped "headless" from that row: stage 03 boots the VM with the GUI attached so the keystroke injection can be observed, so the install is unattended but not headless.
- **Local lint matches CI:** the `Invoke-ScriptAnalyzer` command in `README.md` omitted `-ExcludeRule PSUseBOMForUnicodeEncodedFile`, so running it locally could report a failure CI would not.

### Added
- **Two root-cause entries in `TROUBLESHOOTING.md`:** #14 covers the media-registry UUID mismatch and the silent-success bug that hid it; #15 covers the `known_hosts` collision and why `StrictHostKeyChecking=no` does not prevent it.

### Deferred
- **Stage 03 is still a timing race.** `03-autoinstall-node.ps1` continues to clear Subiquity's destructive-disk confirmation by sleeping 90 seconds and then firing `controlvm keyboardputstring "yes"` at whatever happens to be on screen. Nothing verifies the prompt is displayed, so on a slow disk the keystroke goes nowhere and the install never completes. The correct fix is to pass `autoinstall` on the kernel command line so Subiquity treats the run as fully automated and never asks -- that requires rebuilding the Ubuntu ISO with a patched `boot/grub/grub.cfg`, and neither `xorriso` nor the Windows ADK's `oscdimg` is currently available on the build host. The limitation is now stated in the script header instead of being left implicit, and the 20-minute deadline above bounds the failure rather than letting it hang. That is a mitigation, not a fix.

## [1.8.0] - 2026-07-30
### Changed
- **Problem statement:** Rewrote `README.md`'s "The Problem" around the four constraints the pipeline actually addresses (no usable console, unversioned GUI provisioning, inbound access requiring a router port-forward, hypervisor-side monitoring with no history and no remote access). Replaced the previous list, which described implementation bugs encountered during the build rather than the project's motivating constraints.
- **Metrics table:** Restructured to map 1:1 onto those four problems, with each figure traceable to a source — provisioning time from a measured end-to-end run, scrape interval from `monitoring/prometheus.yml`, and the one unmeasured baseline explicitly marked `(est.)`.

### Fixed
- **Unverified throughput claim:** `README.md` stated the NAT + `virtio` migration took the VM from 5 Mbps to 800+ Mbps. Neither figure was ever benchmarked and the numbers appeared nowhere else in the repository. Replaced with a measurement taken from inside the VM (~210-290 Mbps across four samples) and the observed pre-migration symptom (a Docker pull stalled at ~50% after an hour). Recorded in `TROUBLESHOOTING.md` #7 along with the command used, and noted there that the pre-migration figure was never benchmarked.

## [1.7.0] - 2026-07-29
### Added
- **Single source of truth config:** Added `config/node.json` for VM name, RAM, CPU cores, disk size, and ISO URL, plus a shared `scripts/Get-LabConfig.ps1` loader. `01-host-prep.ps1`, `02-provision-node.ps1`, `03-autoinstall-node.ps1`, `04-connect-node.ps1`, and `Deploy-Node.ps1` all read from it now instead of each hardcoding (and risking drifting out of sync on) their own defaults -- `SRE-Node-01` was previously duplicated independently across four separate files. Explicit command-line arguments still override the config file per-run.

## [1.6.0] - 2026-07-29
### Fixed
- **Stage 01 restart loop:** `bcdedit /enum "{current}"` was mangled by PowerShell's native-argument marshalling and always returned an error instead of real BCD data, making the idempotency check fail closed and re-demand a restart on every run regardless of actual state. Switched to bare `bcdedit /enum`.
- **Stage 02 delete failure:** the VM-wipe path called `unregistervm --delete` without checking if the VM was still running, which fails with "locked for a session" and cascades into every subsequent `VBoxManage` call. Added the same power-off-if-running guard `03-autoinstall-node.ps1` already had.

### Changed
- **Documentation:** Tightened README wording ("fully automated" → "automated", "instant remote access" → names the one-time Tailscale device approval step). Added TROUBLESHOOTING.md entries for the two fixes above, a false-alarm CPU-spike scenario from an unkilled `yes` loop, and why reaching the VM's Tailscale IP requires Tailscale on the connecting device too (including the host).

## [1.5.0] - 2026-07-29
### Added
- **Observability:** Added `node_exporter` to the Docker Compose stack and configured Prometheus to scrape host-level metrics.
- **CI/CD Pipeline:** Added a new parallel Ubuntu runner job to validate the `docker-compose.yml` configuration on pull requests and pushes.

### Changed
- **Secrets Management:** Moved the Grafana admin password from plaintext in `docker-compose.yml` to a `.env` file (with `.env.example` template) and removed plaintext secrets from the repository.
- **Security:** Switched from interactive password authentication to dynamic SSH key injection via cloud-init. Scripts no longer prompt for passwords, enabling true zero-touch provisioning.
- **Documentation:** Updated `README.md` to reflect true zero-touch passwordless SSH key authentication and adjusted the marketing tone. Added troubleshooting steps for console-login fallback.

## [1.4.0] - 2026-07-27
### Added
- **CI/CD Pipeline:** Implemented a GitHub Actions workflow to automatically lint PowerShell scripts using `PSScriptAnalyzer` on every push.
- **Documentation:** Appended CI/CD pipeline details to `README.md`.

### Fixed
- Resolved multiple `PSScriptAnalyzer` warnings across deployment scripts (`Write-Host`, empty catch blocks, unused variables).

## [1.3.0] - 2026-07-23
### Changed & Fixed
| Component | Issue/Feature | Resolution |
| :--- | :--- | :--- |
| **Networking Architecture** | Severe "dial-up" packet drops when bridging VM to Windows Wi-Fi 6 cards | Switched VirtualBox from Bridged to **NAT** and added the `virtio` driver for maximum gigabit performance. |
| **Port Forwarding** | NAT breaks direct IP access from host | Added explicit VirtualBox port forwarding rules (`2222` for SSH, `3000` for Grafana, `9090` for Prometheus). |
| **IP Discovery** | ARP spoofing and GuestProperty fetches were complex and brittle | Removed IP discovery entirely. Scripts now reliably poll `localhost:2222` to detect VM readiness. |
| **PowerShell Redirection** | Scripts failed to find `ssh.exe` on 32-bit processes due to `SysWOW64` redirection | Implemented a dynamic `$env:WINDIR\sysnative` path fallback to cleanly resolve native Windows OpenSSH binaries regardless of architecture. |
| **Interactive Sudo** | `sudo` failed silently in the background because SSH scripts lacked a TTY | Added the `-t` pseudo-TTY flag to `ssh.exe` calls in scripts `05` and `06` to allow interactive password prompts. |
| **Package Resilience** | Violent VM interruptions caused `apt-get` to permanently lock | Injected `sudo dpkg --configure -a` prior to Docker installation in script `06` to automatically heal corrupted package managers. |
| **Execution Policies** | Scripts blocked by `UnauthorizedAccess` policies | Systematically ran `Unblock-File` across the `scripts/` directory to satisfy Windows security restrictions. |

## [1.2.0] - 2026-07-23
### Added
- Created `Deploy-Node.ps1` master orchestration script to sequentially execute all stages, including an asynchronous wait-loop for the headless OS installation.
- Injected `Start-Transcript` logging into all `scripts/` to automatically generate timestamped, per-host execution logs in the `logs/` directory.
- Created `scripts/05-setup-tailscale.ps1` to automate Tailscale installation for secure remote access.
- Created `scripts/06-setup-monitoring.ps1` to automate Docker and monitoring stack deployment.
- Added `monitoring/` directory containing `docker-compose.yml` and `prometheus.yml` for observability.
- Updated root `README.md` with instructions for executing Phase 2 and Phase 3.
- Added `.gitignore` to prevent tracking of transcript `.log` files and VirtualBox `.iso`/`.vdi` artifacts.

## [1.1.1] - 2026-07-19
### Added
- Created `TROUBLESHOOTING.md` to document critical sysops edge cases.
- Injected `debconf_selections` into `user-data` to suppress interactive `grub-pc` prompts during headless installations on BIOS firmware.

### Fixed
- Replaced a broken/dummy SHA-512 password hash in `user-data` with a newly generated, valid cryptographic hash for the `sysadmin` account.
- Disabled apt network updates during `subiquity` installation via `user-data` to prevent the installer from hanging indefinitely on IPv6/Mirror timeouts.
- Fixed an issue where a silently truncated Ubuntu ISO download would cause physical I/O errors and `Hash Sum mismatch` crashes during `subiquity` installation.
- Explicitly standardized on Legacy BIOS (`--firmware bios`) in `02-provision-node.ps1` to avoid VirtualBox UEFI automated bootloop issues.

## [1.1.0] - 2026-07-19
### Added
- Added `scripts/03-autoinstall-node.ps1` to fully automate the Ubuntu Server OS installation.
- Added `scripts/cloud-init/user-data` and `meta-data` templates to support unattended `subiquity` installation via dynamically generated Virtual Hard Disk (VHD).

## [1.0.2] - 2026-07-19
### Fixed
- Aligned internal script stage numbering (Stage 1/2) with script filenames (01/02) for clarity.
- Fixed a bug in `02-provision-node.ps1` where single `Get-NetAdapter` results lacked a `.Count` property, causing the network selection prompt to break.

## [1.0.1] - 2026-07-19
### Fixed
- Fixed `bcdedit` command failures in `01-host-prep.ps1` by resolving its absolute path (resolves WoW64 and PATH issues) and using double quotes for the `{current}` parameter.

## [1.0.0] - 2026-07-18
### Added
- `.gitignore` for standard PowerShell and VirtualBox artifacts.
- `CHANGELOG.md` to track project history.
- MIT License for open-source distribution.
- Automated Active Network Adapter Detection for VirtualBox bridging.

### Changed
- Reorganized repository structure to follow standard practices (moved scripts to `scripts/` directory).
- Consolidated fragmented documentation into a single root `README.md`.
- Converted `02-provision-node.sh` to `02-provision-node.ps1` for native Windows execution without Git Bash.
- Refactored `01-host-prep.ps1` to include `try/catch` error handling, parameterized variables, and idempotent virtualization feature handling.

### Removed
- `01-Setup` directory (replaced by `scripts/`).
- `02-provision-node.sh` (replaced by pure PowerShell equivalent).
