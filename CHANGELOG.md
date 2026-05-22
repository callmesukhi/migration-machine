# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-05-22

Initial release.

### Added
- `migrate` entrypoint with `capture`, `provision`, `restore`, and `bootstrap` commands.
- Manifest-driven provisioning engine with per-step validation, required/optional
  steps, dry-run, and single-step (`--only`) execution.
- Progress UI that auto-detects swiftDialog (GUI) and falls back to a CLI list.
- Modular step scripts: Xcode CLT, package manager (Homebrew or MacPorts),
  packages, secrets, dotfiles, macOS defaults, config restore, TouchID-for-sudo.
- `capture`/`restore` for exporting and reapplying config, with an AES-256
  encrypted secrets bundle.
- Tool/data decoupling via `MIGRATION_DATA` (or `--data`).
- Example manifests for Homebrew and MacPorts machines.
