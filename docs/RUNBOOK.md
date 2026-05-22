# Migration runbook

The end-to-end procedure, plus the parts no script can do for you. Read the manual checklist before you start; it is the difference between a smooth first day and a week of "why is this broken".

## 1. On the OLD Mac

1. Give your terminal Full Disk Access (System Settings > Privacy & Security > Full Disk Access). Some files (Safari bookmarks, protected folders) are unreadable otherwise and will silently skip.
2. Clone the repo and capture:

   ```bash
   git clone https://github.com/YOUR_GITHUB_USERNAME/migration-machine.git
   cd migration-machine
   ./migrate --data ~/Sync/migration capture
   ```

3. Set a strong passphrase for the encrypted secrets bundle when prompted, and store it in your password manager. Losing it makes the bundle unrecoverable.
4. Review `~/Sync/migration/logs/capture-*.log` for anything important that got skipped.
5. Let your transport (cloud sync, drive) finish copying `~/Sync/migration`.

## 2. On the NEW Mac

1. Clone the repo, pick and edit a manifest:

   ```bash
   git clone https://github.com/YOUR_GITHUB_USERNAME/migration-machine.git
   cd migration-machine
   cp manifests/example-homebrew.json manifests/local-mymac.json
   $EDITOR manifests/local-mymac.json     # set dotfilesRepo, etc.
   ```

2. Dry run first. It changes nothing:

   ```bash
   ./migrate --data ~/Sync/migration provision -m local-mymac --dry-run
   ```

3. Provision for real (bootstrap installs Xcode CLT first on a bare Mac):

   ```bash
   ./migrate --data ~/Sync/migration bootstrap -m local-mymac
   ```

4. Open a fresh terminal so the new shell and Homebrew environment load.

Run from a Terminal, not a pure GUI launch: secrets restore prompts for the passphrase and several steps use `sudo`.

## 3. The manual checklist (no script does these)

- [ ] Re-grant per-app permissions: Full Disk Access, Accessibility, Screen Recording, Input Monitoring, Automation. These live in macOS's TCC database and are deliberately not transferable. Window managers, launchers, clipboard tools, and screen recorders will each need this.
- [ ] Sign back into apps (Slack, 1Password, browsers, Spotify, Zoom). Preferences restore; sessions do not.
- [ ] Re-enter license keys for paid, non-subscription apps.
- [ ] Keychain. Passwords, Wi-Fi, and certificates do not move with these scripts. Turn on iCloud Keychain on both Macs and let it sync, or export specific items from Keychain Access. Much of "why is this not working" traces back to a missing Keychain entry.
- [ ] Browser profiles. Sign into your browser account to restore extensions and history; the captured bookmarks are a safety net, not the primary path.
- [ ] Your data: Documents, Photos, Mail, Messages, large repos. This tool is config only. Move data separately.
- [ ] Verify keys: `ssh-add -l` and a test `git fetch`; `gpg --list-secret-keys`.

## Troubleshooting

- A file you expected is missing from capture: check the capture log for a `WARN`. Usual cause is Full Disk Access not granted. Grant it and re-run.
- `defaults import` failed for an app: install the app first, then `./migrate provision -m <manifest> --only restore-config`.
- An app ignored its restored prefs: it was running during import and overwrote them on quit. Quit it and restore again.
- MacPorts step stops: set `config.macportsPkgUrl` to the `.pkg` for your macOS version.
- VS Code extensions did not install: enable the `code` CLI in VS Code (Shell Command: Install 'code' command in PATH), then re-run the relevant step.
