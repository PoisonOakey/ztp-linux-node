# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
