# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-05-27

First tagged release.

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
- `tests/run.sh` engine test harness with fixtures, covering validation
  skip/confirm, dry-run, `--only`, and optional vs. required failure.
- GitHub Actions CI: engine tests (gating) and shellcheck (advisory).
- README "Status & testing" section with a "Tested on" table.
- Project website under `site/`, deployed to GitHub Pages at
  migration-machine.callmesukhi.com via the `pages` workflow.
- `site` workflow and `tests/check-site.sh`: validate that each page parses and
  that all `href`/`src` links and assets resolve, on PRs touching `site/`.
- README banner and CI/site/pages status badges.
- Guided GUI setup: `migrate wizard`, a swiftDialog front-end over the engine
  that builds a manifest from a few prompts and previews it before applying.
- One-line installer (`site/install.sh`, served from the site) for a no-git
  bootstrap that downloads the tool and launches the wizard.
- Homebrew formula under `packaging/homebrew/` for `brew install` distribution.
