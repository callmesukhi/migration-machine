#!/usr/bin/env bash
#
# capture.sh - Export Mac configuration for migration to a new machine.
#
# RUN THIS ON YOUR OLD MAC.
#
# It writes everything into subfolders next to this script (payload/, manifest/,
# secrets/, logs/). Because this script lives inside your synced OneDrive folder,
# the exported config syncs to the new Mac automatically. Then run restore.sh there.
#
# Design notes:
#   - Read-only against your system. It never modifies your old Mac, only writes
#     into the migration folder.
#   - Resilient: missing files/apps are skipped, not fatal.
#   - macOS bash 3.2 compatible (no associative arrays, no mapfile).
#   - Secrets (SSH/GPG keys, tokens) go into an AES-256 encrypted .dmg, never plaintext.
#
# Usage:
#   bash capture.sh              # capture everything that is enabled below
#   CAPTURE_SECRETS=0 bash capture.sh   # skip the encrypted secrets bundle
#
set -o pipefail

# ----------------------------------------------------------------------------
# Config toggles (override by exporting before running, e.g. CAPTURE_BROWSER=0)
# ----------------------------------------------------------------------------
: "${CAPTURE_DEV:=1}"        # shell, git, homebrew, editors, language tools
: "${CAPTURE_APPS:=1}"       # third-party app preferences
: "${CAPTURE_MACOS:=1}"      # macOS system defaults
: "${CAPTURE_BROWSER:=1}"    # browser bookmarks + extension inventory
: "${CAPTURE_SECRETS:=1}"    # encrypted secrets bundle

# ----------------------------------------------------------------------------
# Resolve paths. Outputs go to the migration DATA directory, which is decoupled
# from the tool repo so the captured data can be carried between machines.
# Set MIGRATION_DATA (or pass --data via the `migrate` dispatcher).
# ----------------------------------------------------------------------------
: "${MIGRATION_DATA:=$HOME/migration-data}"
BASE="$MIGRATION_DATA"
mkdir -p "$BASE"

PAYLOAD="$BASE/payload"
MANIFEST="$BASE/manifest"
SECRETS_DIR="$BASE/secrets"
LOGS="$BASE/logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGS/capture-$STAMP.log"

mkdir -p "$PAYLOAD" "$MANIFEST" "$SECRETS_DIR" "$LOGS"
mkdir -p "$MANIFEST/macos-defaults"

# ----------------------------------------------------------------------------
# Logging helpers
# ----------------------------------------------------------------------------
log()  { printf '%s\n' "$*" | tee -a "$LOG"; }
warn() { printf 'WARN: %s\n' "$*" | tee -a "$LOG" >&2; }
section() { printf '\n==== %s ====\n' "$*" | tee -a "$LOG"; }

# Copy a single file (preserving it) into PAYLOAD/<rel>/. Skips if missing.
copy_file() {
  local src="$1" rel="$2"
  [ -e "$src" ] || return 0
  local destdir="$PAYLOAD/$rel"
  mkdir -p "$destdir"
  if cp -p "$src" "$destdir"/ 2>>"$LOG"; then
    log "  + $src"
  else
    warn "  could not copy $src"
  fi
}

# Copy a directory into PAYLOAD/<rel>/. Extra args are rsync excludes.
copy_dir() {
  local src="$1" rel="$2"; shift 2
  [ -d "$src" ] || return 0
  local destdir="$PAYLOAD/$rel"
  mkdir -p "$destdir"
  local base; base="$(basename "$src")"
  mkdir -p "$destdir/$base"
  if command -v rsync >/dev/null 2>&1; then
    local exargs=()
    local ex
    for ex in "$@"; do exargs+=( --exclude "$ex" ); done
    # Intentional word-splitting of the (possibly empty) excludes array.
    # shellcheck disable=SC2086
    if rsync -a ${exargs[@]+"${exargs[@]}"} "$src"/ "$destdir/$base"/ 2>>"$LOG"; then
      log "  + $src/  (dir)"
    else
      warn "  rsync failed for $src, falling back to cp"
      cp -pR "$src"/. "$destdir/$base"/ 2>>"$LOG" && log "  + $src/ (cp)" || warn "  cp failed for $src"
    fi
  else
    cp -pR "$src"/. "$destdir/$base"/ 2>>"$LOG" && log "  + $src/ (cp)" || warn "  cp failed for $src"
  fi
}

# ----------------------------------------------------------------------------
# DEV TOOLCHAIN
# ----------------------------------------------------------------------------
capture_dev() {
  section "Dev toolchain"

  log "Shell + core dotfiles"
  local f
  for f in \
    .zshrc .zprofile .zshenv .zlogin .bashrc .bash_profile .profile .inputrc \
    .aliases .functions .exports .path .extra \
    .gitconfig .gitignore_global .gitattributes .git-commit-template \
    .vimrc .ideavimrc .tmux.conf .curlrc .wgetrc .editorconfig \
    .tool-versions .asdfrc .nvmrc .ruby-version .python-version \
    .digrc .screenrc .hushlogin .p10k.zsh
  do
    copy_file "$HOME/$f" "dotfiles"
  done

  log "SSH config (public config only; private keys go in the secrets bundle)"
  copy_file "$HOME/.ssh/config" "dotfiles/ssh"
  copy_file "$HOME/.ssh/known_hosts" "dotfiles/ssh"

  log "Config dirs under ~/.config (allowlist of safe tool configs)"
  local c
  for c in \
    nvim karabiner alacritty kitty wezterm starship.toml tmux \
    bat ripgrep gh lazygit lsd btop neofetch fastfetch zellij \
    helix atuin direnv k9s warp espanso raycast
  do
    if [ -d "$HOME/.config/$c" ]; then
      copy_dir "$HOME/.config/$c" "config" \
        "*cache*" "*Cache*" "*.log" "hosts.yml"   # gh hosts.yml holds a token -> secrets bundle
    elif [ -f "$HOME/.config/$c" ]; then
      copy_file "$HOME/.config/$c" "config"
    fi
  done

  log "Oh-My-Zsh / prezto / starship customizations"
  copy_dir "$HOME/.oh-my-zsh/custom" "shell-frameworks" "*cache*"
  copy_file "$HOME/.zpreztorc" "dotfiles"

  log "Homebrew bundle (formulae, casks, taps, Mac App Store apps)"
  if command -v brew >/dev/null 2>&1; then
    brew bundle dump --force --describe --file="$MANIFEST/Brewfile" 2>>"$LOG" \
      && log "  + Brewfile written" || warn "  brew bundle dump failed"
    brew list --versions > "$MANIFEST/brew-list-versions.txt" 2>>"$LOG"
    brew --version > "$MANIFEST/brew-version.txt" 2>>"$LOG"
  else
    warn "  Homebrew not found in PATH; skipping Brewfile"
  fi

  log "Editor settings (VS Code / Cursor / VSCodium)"
  capture_editor "code"   "Code"
  capture_editor "cursor" "Cursor"
  capture_editor "codium" "VSCodium"

  log "JetBrains, Sublime configs (if present)"
  copy_dir "$HOME/Library/Application Support/Sublime Text/Packages/User" "editors/sublime" "*cache*"
  # JetBrains stores config under ~/Library/Application Support/JetBrains/<Product>/options
  if [ -d "$HOME/Library/Application Support/JetBrains" ]; then
    ls "$HOME/Library/Application Support/JetBrains" > "$MANIFEST/jetbrains-products.txt" 2>>"$LOG"
    log "  + listed JetBrains products (settings sync via JetBrains account recommended)"
  fi

  log "Language / version manager inventories"
  command -v node >/dev/null 2>&1 && node --version > "$MANIFEST/node-version.txt" 2>>"$LOG"
  command -v nvm  >/dev/null 2>&1 && nvm ls --no-colors > "$MANIFEST/nvm-versions.txt" 2>>"$LOG"
  command -v pyenv >/dev/null 2>&1 && pyenv versions > "$MANIFEST/pyenv-versions.txt" 2>>"$LOG"
  command -v rbenv >/dev/null 2>&1 && rbenv versions > "$MANIFEST/rbenv-versions.txt" 2>>"$LOG"
  command -v asdf >/dev/null 2>&1 && asdf plugin list --urls > "$MANIFEST/asdf-plugins.txt" 2>>"$LOG"
  command -v pipx >/dev/null 2>&1 && pipx list > "$MANIFEST/pipx-list.txt" 2>>"$LOG"
  command -v npm  >/dev/null 2>&1 && npm ls -g --depth=0 > "$MANIFEST/npm-global.txt" 2>>"$LOG"
  command -v gem  >/dev/null 2>&1 && gem list > "$MANIFEST/gem-list.txt" 2>>"$LOG"
  command -v cargo >/dev/null 2>&1 && cargo install --list > "$MANIFEST/cargo-installed.txt" 2>>"$LOG"
  command -v code >/dev/null 2>&1 || true

  log "crontab"
  crontab -l > "$MANIFEST/crontab.txt" 2>/dev/null && log "  + crontab captured" || true
}

# Capture a VS Code-family editor's user settings + extension list.
capture_editor() {
  local cli="$1" appdir="$2"
  local userdir="$HOME/Library/Application Support/$appdir/User"
  if [ -d "$userdir" ]; then
    copy_file "$userdir/settings.json"    "editors/$appdir"
    copy_file "$userdir/keybindings.json" "editors/$appdir"
    copy_dir  "$userdir/snippets"         "editors/$appdir"
  fi
  if command -v "$cli" >/dev/null 2>&1; then
    "$cli" --list-extensions > "$MANIFEST/$cli-extensions.txt" 2>>"$LOG" \
      && log "  + $cli extension list" || true
  fi
}

# ----------------------------------------------------------------------------
# APP PREFERENCES
# ----------------------------------------------------------------------------
capture_apps() {
  section "App preferences"

  # Curated allowlist of preference domains for common power-user apps.
  # Add your own bundle IDs here. Find one with: osascript -e 'id of app "AppName"'
  local domains="
com.googlecode.iterm2
com.knollsoft.Rectangle
com.knollsoft.Hookshot
com.crowdcafe.windowmagnet
com.runningwithcrayons.Alfred-Preferences
com.raycast.macos
com.surteesstudios.Bartender
com.if.Amphetamine
com.flexibits.fantastical2.mac
com.culturedcode.ThingsMac
net.shinyfrog.bear
com.automattic.simplenote
md.obsidian
com.tinyspeck.slackmacgap
us.zoom.xos
com.hnc.Discord
com.spotify.client
org.hammerspoon.Hammerspoon
org.pqrs.Karabiner-Elements.Settings
com.lwouis.alt-tab-macos
com.mowglii.ItsycalApp
com.apple.Terminal
com.sindresorhus.Velja
com.getcleanshot.app
com.colliderli.iina
"
  local d
  for d in $domains; do
    [ -z "$d" ] && continue
    if defaults export "$d" "$MANIFEST/app-prefs-$d.plist" 2>/dev/null; then
      log "  + prefs $d"
    fi
  done

  log "Per-app Application Support (config, not caches)"
  copy_dir "$HOME/Library/Application Support/Alfred" "app-support/Alfred" "*cache*" "Databases"
  copy_dir "$HOME/.hammerspoon" "app-support/hammerspoon" "*cache*"
  copy_dir "$HOME/Library/Application Support/espanso" "app-support/espanso" "*cache*"

  log "User fonts"
  copy_dir "$HOME/Library/Fonts" "fonts"

  log "Inventories so you can cherry-pick more later"
  ls -1 /Applications > "$MANIFEST/applications.txt" 2>/dev/null
  ls -1 "$HOME/Applications" >> "$MANIFEST/applications.txt" 2>/dev/null
  ls -1 "$HOME/Library/Preferences" > "$MANIFEST/all-preference-domains.txt" 2>/dev/null
  ls -1 "$HOME/Library/Containers" > "$MANIFEST/sandboxed-containers.txt" 2>/dev/null
  osascript -e 'tell application "System Events" to get the name of every login item' \
    > "$MANIFEST/login-items.txt" 2>/dev/null && log "  + login items" || true
}

# ----------------------------------------------------------------------------
# macOS SYSTEM DEFAULTS
# ----------------------------------------------------------------------------
capture_macos() {
  section "macOS system defaults"

  # Curated UI/UX domains. Exported as plists; restore re-imports them with types intact.
  local sysdomains="
NSGlobalDomain
com.apple.dock
com.apple.finder
com.apple.screencapture
com.apple.screensaver
com.apple.menuextra.clock
com.apple.controlcenter
com.apple.controlstrip
com.apple.HIToolbox
com.apple.symbolichotkeys
com.apple.universalaccess
com.apple.WindowManager
com.apple.spaces
com.apple.AppleMultitouchTrackpad
com.apple.driver.AppleBluetoothMultitouch.trackpad
com.apple.driver.AppleBluetoothMultitouch.mouse
com.apple.AppleMultitouchMouse
com.apple.keyboard
com.apple.print.PrintingPrefs
com.apple.desktopservices
com.apple.TextInputMenu
com.apple.systemuiserver
com.apple.dock.extra
"
  local d
  for d in $sysdomains; do
    [ -z "$d" ] && continue
    if defaults export "$d" "$MANIFEST/macos-defaults/$d.plist" 2>/dev/null; then
      log "  + defaults $d"
    fi
  done

  # Full list of every domain present, so you can grab more by hand if needed.
  defaults domains 2>/dev/null | tr ',' '\n' | sed 's/^ *//' > "$MANIFEST/macos-all-domains.txt"
  log "  + full domain list written to manifest/macos-all-domains.txt"

  # A few useful global readouts.
  {
    echo "# Captured $(date)"
    echo "# Reference values; restore.sh imports the plists above rather than these."
    echo "computer_name: $(scutil --get ComputerName 2>/dev/null)"
    echo "host_name:     $(scutil --get LocalHostName 2>/dev/null)"
    echo "key_repeat:    $(defaults read NSGlobalDomain KeyRepeat 2>/dev/null)"
    echo "initial_repeat:$(defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null)"
  } > "$MANIFEST/macos-summary.txt" 2>/dev/null
}

# ----------------------------------------------------------------------------
# BROWSERS
# ----------------------------------------------------------------------------
capture_browser() {
  section "Browser setup"
  log "NOTE: For Chrome/Arc/Firefox, signing into your account on the new Mac restores"
  log "      bookmarks, history, and extensions far more reliably than copying files."
  log "      This step captures bookmarks + an extension inventory as a safety net."

  # Chrome / Chromium family
  local chrome="$HOME/Library/Application Support/Google/Chrome"
  if [ -d "$chrome" ]; then
    copy_file "$chrome/Default/Bookmarks" "browser/chrome/Default"
    copy_file "$chrome/Default/Preferences" "browser/chrome/Default"
    [ -d "$chrome/Default/Extensions" ] && \
      ls -1 "$chrome/Default/Extensions" > "$MANIFEST/chrome-extension-ids.txt" 2>/dev/null
    log "  + Chrome bookmarks + extension IDs"
  fi

  # Brave / Edge / Vivaldi bookmarks
  copy_file "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Bookmarks" "browser/brave/Default"
  copy_file "$HOME/Library/Application Support/Microsoft Edge/Default/Bookmarks" "browser/edge/Default"

  # Arc
  [ -d "$HOME/Library/Application Support/Arc" ] && log "  Arc detected: use your Arc account to sync; spaces/tabs are account-bound."

  # Firefox: capture profiles.ini + bookmark backups
  local ff="$HOME/Library/Application Support/Firefox"
  if [ -d "$ff" ]; then
    copy_file "$ff/profiles.ini" "browser/firefox"
    # bookmarkbackups are compact JSONLZ4 snapshots of bookmarks
    local prof
    for prof in "$ff"/Profiles/*; do
      [ -d "$prof/bookmarkbackups" ] && copy_dir "$prof/bookmarkbackups" "browser/firefox/$(basename "$prof")"
    done
    log "  + Firefox profiles.ini + bookmark backups"
  fi

  # Safari bookmarks need Full Disk Access for Terminal; will silently skip otherwise.
  copy_file "$HOME/Library/Safari/Bookmarks.plist" "browser/safari"
}

# ----------------------------------------------------------------------------
# SECRETS -> AES-256 encrypted DMG
# ----------------------------------------------------------------------------
capture_secrets() {
  section "Secrets (encrypted)"

  if ! command -v hdiutil >/dev/null 2>&1; then
    warn "hdiutil not available; skipping secrets bundle."
    return 0
  fi

  local stage; stage="$(mktemp -d "${TMPDIR:-/tmp}/migsecrets.XXXXXX")" || { warn "could not make temp dir"; return 1; }
  log "Staging secret material in a temp dir (removed after encryption): $stage"

  # Helper to stage a path preserving structure under the stage root.
  stage_path() {
    local src="$1"
    [ -e "$src" ] || return 0
    local rel="${src#$HOME/}"
    local dest="$stage/$rel"
    mkdir -p "$(dirname "$dest")"
    cp -pR "$src" "$dest" 2>/dev/null && log "  staged ~/${rel}"
  }

  # SSH private keys + the whole .ssh (config too, harmless to duplicate)
  stage_path "$HOME/.ssh"
  # GPG keyring
  stage_path "$HOME/.gnupg"
  # Cloud / registry / service credentials
  stage_path "$HOME/.aws"
  stage_path "$HOME/.config/gh/hosts.yml"
  stage_path "$HOME/.npmrc"
  stage_path "$HOME/.netrc"
  stage_path "$HOME/.git-credentials"
  stage_path "$HOME/.docker/config.json"
  stage_path "$HOME/.kube/config"
  stage_path "$HOME/.pypirc"
  stage_path "$HOME/.config/gcloud"
  stage_path "$HOME/.terraformrc"

  # Anything the user dropped into a manual extras list, one path per line.
  if [ -f "$BASE/secrets-extra-paths.txt" ]; then
    local p
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      case "$p" in \#*) continue;; esac
      # Expand a leading ~
      case "$p" in "~"*) p="$HOME${p#\~}";; esac
      stage_path "$p"
    done < "$BASE/secrets-extra-paths.txt"
  fi

  if [ -z "$(ls -A "$stage" 2>/dev/null)" ]; then
    log "No secret files found to bundle. Skipping."
    rm -rf "$stage"
    return 0
  fi

  # Prompt for a passphrase (twice).
  local pw1 pw2
  printf 'Set a passphrase for the encrypted secrets bundle: '
  stty -echo 2>/dev/null; read -r pw1; stty echo 2>/dev/null; printf '\n'
  printf 'Confirm passphrase: '
  stty -echo 2>/dev/null; read -r pw2; stty echo 2>/dev/null; printf '\n'
  if [ "$pw1" != "$pw2" ] || [ -z "$pw1" ]; then
    warn "Passphrases did not match or were empty. Aborting secrets bundle."
    rm -rf "$stage"
    return 1
  fi

  local dmg="$SECRETS_DIR/secrets.dmg"
  rm -f "$dmg"
  if printf '%s' "$pw1" | hdiutil create \
        -srcfolder "$stage" \
        -encryption AES-256 \
        -stdinpass \
        -volname "MigrationSecrets" \
        -format UDZO \
        "$dmg" >>"$LOG" 2>&1; then
    log "  + Encrypted secrets bundle written: $dmg"
  else
    warn "  hdiutil failed to create the encrypted bundle. See log."
  fi

  # Best-effort cleanup of the plaintext staging copy.
  rm -rf "$stage"
  log "  staging removed. NOTE: on APFS, deletion is not a guaranteed secure erase."
}

# ----------------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------------
main() {
  log "Migration capture started $(date)"
  log "Output base: $BASE"
  log "macOS: $(sw_vers -productVersion 2>/dev/null)  Host: $(hostname 2>/dev/null)"

  [ "$CAPTURE_DEV" = "1" ]     && capture_dev
  [ "$CAPTURE_APPS" = "1" ]    && capture_apps
  [ "$CAPTURE_MACOS" = "1" ]   && capture_macos
  [ "$CAPTURE_BROWSER" = "1" ] && capture_browser
  [ "$CAPTURE_SECRETS" = "1" ] && capture_secrets

  section "Done"
  log "Captured into:"
  log "  payload/   config files"
  log "  manifest/  inventories (Brewfile, extension lists, defaults plists)"
  log "  secrets/   encrypted bundle (if created)"
  log "  logs/      this run's log"
  log ""
  log "Next: let OneDrive finish syncing, then run restore.sh on the new Mac."
  log "Full log: $LOG"
}

main "$@"
