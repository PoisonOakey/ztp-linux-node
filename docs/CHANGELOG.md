# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
