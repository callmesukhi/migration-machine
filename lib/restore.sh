#!/usr/bin/env bash
#
# restore.sh - Reapply captured Mac configuration on a NEW machine.
#
# RUN THIS ON YOUR NEW MAC, after OneDrive has fully synced the migration folder.
#
# Safety model:
#   - Non-destructive. Any existing file it would overwrite is first copied into
#     a timestamped backup folder (backups/restore-<stamp>/).
#   - Supports a dry run so you can see exactly what it will touch first.
#   - Asks before each phase. Use --yes to accept all.
#
# Usage:
#   bash restore.sh --dry-run     # show what would happen, change nothing
#   bash restore.sh               # interactive, confirm each phase
#   bash restore.sh --yes         # run all phases without prompting
#
# You can also run a single phase:
#   bash restore.sh --only brew|dotfiles|config|editors|apps|macos|browser|secrets|fonts
#
set -o pipefail

DRY_RUN=0
ASSUME_YES=0
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --only)    shift; ONLY="$1" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
  shift
done

# ----------------------------------------------------------------------------
# Resolve paths. Reads from the migration DATA directory (decoupled from the
# tool repo). Set MIGRATION_DATA (or pass --data via the `migrate` dispatcher).
# ----------------------------------------------------------------------------
: "${MIGRATION_DATA:=$HOME/migration-data}"
BASE="$MIGRATION_DATA"

PAYLOAD="$BASE/payload"
MANIFEST="$BASE/manifest"
SECRETS_DIR="$BASE/secrets"
LOGS="$BASE/logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGS/restore-$STAMP.log"
BACKUP="$BASE/backups/restore-$STAMP"

mkdir -p "$LOGS" "$BACKUP"

log()  { printf '%s\n' "$*" | tee -a "$LOG"; }
warn() { printf 'WARN: %s\n' "$*" | tee -a "$LOG" >&2; }
section() { printf '\n==== %s ====\n' "$*" | tee -a "$LOG"; }

confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  printf '%s [y/N] ' "$1"
  local a; read -r a
  case "$a" in [yY]|[yY][eE][sS]) return 0;; *) return 1;; esac
}

# Decide whether a given phase should run, honoring --only.
should_run() {
  [ -z "$ONLY" ] && return 0
  [ "$ONLY" = "$1" ] && return 0
  return 1
}

# Copy a file/dir to a destination, backing up anything it would overwrite.
# Directories are merged into the destination (not nested inside it), which is
# why we use rsync / "src/." semantics rather than a plain cp -R src dest.
backup_then_copy() {
  local src="$1" dest="$2"
  [ -e "$src" ] || return 0
  if [ -e "$dest" ]; then
    local rel="${dest#$HOME/}"
    if [ "$DRY_RUN" = "1" ]; then
      log "  DRY: backup existing $dest"
    else
      mkdir -p "$(dirname "$BACKUP/$rel")"
      cp -pR "$dest" "$BACKUP/$rel" 2>>"$LOG"
    fi
  fi
  if [ "$DRY_RUN" = "1" ]; then
    log "  DRY: copy $src -> $dest"
    return 0
  fi
  if [ -d "$src" ]; then
    mkdir -p "$dest"
    if command -v rsync >/dev/null 2>&1; then
      # --ignore-times: the captured payload is authoritative, so overwrite
      # destination files even when size + mtime happen to match.
      rsync -a --ignore-times "$src"/ "$dest"/ 2>>"$LOG" && log "  restored $dest/" || warn "  failed $dest"
    else
      cp -pR "$src"/. "$dest"/ 2>>"$LOG" && log "  restored $dest/" || warn "  failed $dest"
    fi
  else
    mkdir -p "$(dirname "$dest")"
    if cp -pR "$src" "$dest" 2>>"$LOG"; then log "  restored $dest"; else warn "  failed $dest"; fi
  fi
}

# ----------------------------------------------------------------------------
# PHASE: Homebrew + Brewfile
# ----------------------------------------------------------------------------
phase_brew() {
  should_run brew || return 0
  section "Homebrew + packages"
  [ -f "$MANIFEST/Brewfile" ] || { log "No Brewfile found; skipping."; return 0; }
  confirm "Install Homebrew (if missing) and everything in the Brewfile?" || { log "Skipped."; return 0; }

  if ! command -v brew >/dev/null 2>&1; then
    if [ "$DRY_RUN" = "1" ]; then
      log "  DRY: would install Homebrew"
    else
      log "  Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
  fi
  # Put brew on PATH for both Apple Silicon and Intel layouts.
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [ -x /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

  if [ "$DRY_RUN" = "1" ]; then
    log "  DRY: brew bundle install --file=$MANIFEST/Brewfile"
  elif command -v brew >/dev/null 2>&1; then
    log "  Running brew bundle (this can take a while)..."
    brew bundle install --file="$MANIFEST/Brewfile" 2>&1 | tee -a "$LOG"
  else
    warn "  brew still not on PATH; open a new terminal and re-run with --only brew"
  fi
}

# ----------------------------------------------------------------------------
# PHASE: dotfiles
# ----------------------------------------------------------------------------
phase_dotfiles() {
  should_run dotfiles || return 0
  section "Dotfiles"
  [ -d "$PAYLOAD/dotfiles" ] || { log "No dotfiles captured; skipping."; return 0; }
  confirm "Restore shell/git/etc dotfiles into your home folder?" || { log "Skipped."; return 0; }

  local item base
  for item in "$PAYLOAD"/dotfiles/.*; do
    base="$(basename "$item")"
    case "$base" in .|..|ssh) continue;; esac
    [ -e "$item" ] && backup_then_copy "$item" "$HOME/$base"
  done

  # SSH public config (private keys come from the secrets phase).
  if [ -d "$PAYLOAD/dotfiles/ssh" ]; then
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh" 2>/dev/null
    [ -f "$PAYLOAD/dotfiles/ssh/config" ]      && backup_then_copy "$PAYLOAD/dotfiles/ssh/config" "$HOME/.ssh/config"
    [ -f "$PAYLOAD/dotfiles/ssh/known_hosts" ] && backup_then_copy "$PAYLOAD/dotfiles/ssh/known_hosts" "$HOME/.ssh/known_hosts"
  fi

  [ -d "$PAYLOAD/shell-frameworks/custom" ] && backup_then_copy "$PAYLOAD/shell-frameworks/custom" "$HOME/.oh-my-zsh/custom"
}

# ----------------------------------------------------------------------------
# PHASE: ~/.config
# ----------------------------------------------------------------------------
phase_config() {
  should_run config || return 0
  section "~/.config tool configs"
  [ -d "$PAYLOAD/config" ] || { log "No ~/.config captured; skipping."; return 0; }
  confirm "Restore ~/.config tool directories?" || { log "Skipped."; return 0; }
  mkdir -p "$HOME/.config"
  local item base
  for item in "$PAYLOAD"/config/*; do
    [ -e "$item" ] || continue
    base="$(basename "$item")"
    backup_then_copy "$item" "$HOME/.config/$base"
  done
}

# ----------------------------------------------------------------------------
# PHASE: editors
# ----------------------------------------------------------------------------
phase_editors() {
  should_run editors || return 0
  section "Editors (VS Code / Cursor / VSCodium)"
  confirm "Restore editor settings and reinstall extensions?" || { log "Skipped."; return 0; }

  restore_editor "Code"     "code"
  restore_editor "Cursor"   "cursor"
  restore_editor "VSCodium" "codium"
}

restore_editor() {
  local appdir="$1" cli="$2"
  local userdir="$HOME/Library/Application Support/$appdir/User"
  if [ -d "$PAYLOAD/editors/$appdir" ]; then
    [ -f "$PAYLOAD/editors/$appdir/settings.json" ]    && backup_then_copy "$PAYLOAD/editors/$appdir/settings.json" "$userdir/settings.json"
    [ -f "$PAYLOAD/editors/$appdir/keybindings.json" ] && backup_then_copy "$PAYLOAD/editors/$appdir/keybindings.json" "$userdir/keybindings.json"
    [ -d "$PAYLOAD/editors/$appdir/snippets" ]          && backup_then_copy "$PAYLOAD/editors/$appdir/snippets" "$userdir/snippets"
  fi
  local listfile="$MANIFEST/$cli-extensions.txt"
  if command -v "$cli" >/dev/null 2>&1 && [ -f "$listfile" ]; then
    local ext
    while IFS= read -r ext; do
      [ -z "$ext" ] && continue
      if [ "$DRY_RUN" = "1" ]; then log "  DRY: $cli --install-extension $ext"; else
        "$cli" --install-extension "$ext" >>"$LOG" 2>&1 && log "  ext $ext" || warn "  failed ext $ext"
      fi
    done < "$listfile"
  elif [ -f "$listfile" ]; then
    log "  $cli CLI not on PATH; install $appdir first, then: cat '$listfile' | xargs -L1 $cli --install-extension"
  fi
}

# ----------------------------------------------------------------------------
# PHASE: app preferences
# ----------------------------------------------------------------------------
phase_apps() {
  should_run apps || return 0
  section "App preferences"
  confirm "Import third-party app preference domains?" || { log "Skipped."; return 0; }

  local plist domain
  for plist in "$MANIFEST"/app-prefs-*.plist; do
    [ -e "$plist" ] || continue
    domain="$(basename "$plist")"; domain="${domain#app-prefs-}"; domain="${domain%.plist}"
    if [ "$DRY_RUN" = "1" ]; then
      log "  DRY: defaults import $domain $plist"
    else
      defaults import "$domain" "$plist" 2>>"$LOG" && log "  imported $domain" || warn "  failed import $domain"
    fi
  done

  [ -d "$PAYLOAD/app-support/Alfred" ]      && backup_then_copy "$PAYLOAD/app-support/Alfred" "$HOME/Library/Application Support/Alfred"
  [ -d "$PAYLOAD/app-support/hammerspoon" ] && backup_then_copy "$PAYLOAD/app-support/hammerspoon" "$HOME/.hammerspoon"
  [ -d "$PAYLOAD/app-support/espanso" ]     && backup_then_copy "$PAYLOAD/app-support/espanso" "$HOME/Library/Application Support/espanso"
  log "  Note: quit an app before importing its prefs, or it may overwrite them on quit."
}

# ----------------------------------------------------------------------------
# PHASE: macOS defaults
# ----------------------------------------------------------------------------
phase_macos() {
  should_run macos || return 0
  section "macOS system defaults"
  [ -d "$MANIFEST/macos-defaults" ] || { log "No macOS defaults captured; skipping."; return 0; }
  confirm "Import macOS system defaults (Dock, Finder, keyboard, etc.)?" || { log "Skipped."; return 0; }

  local plist domain
  for plist in "$MANIFEST"/macos-defaults/*.plist; do
    [ -e "$plist" ] || continue
    domain="$(basename "$plist")"; domain="${domain%.plist}"
    if [ "$DRY_RUN" = "1" ]; then
      log "  DRY: defaults import $domain $plist"
    else
      defaults import "$domain" "$plist" 2>>"$LOG" && log "  imported $domain" || warn "  failed import $domain"
    fi
  done

  if [ "$DRY_RUN" != "1" ]; then
    log "  Restarting Dock, Finder, SystemUIServer to apply..."
    killall Dock 2>/dev/null
    killall Finder 2>/dev/null
    killall SystemUIServer 2>/dev/null
  fi
  log "  Some settings only take effect after logout/restart."
}

# ----------------------------------------------------------------------------
# PHASE: browsers
# ----------------------------------------------------------------------------
phase_browser() {
  should_run browser || return 0
  section "Browsers"
  log "Recommended: sign into Chrome/Arc/Firefox accounts first; that restores"
  log "bookmarks, history, and extensions cleanly. Below just restores bookmark files."
  confirm "Restore captured browser bookmark files?" || { log "Skipped."; return 0; }

  backup_then_copy "$PAYLOAD/browser/chrome/Default/Bookmarks" "$HOME/Library/Application Support/Google/Chrome/Default/Bookmarks"
  backup_then_copy "$PAYLOAD/browser/brave/Default/Bookmarks"  "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Bookmarks"
  backup_then_copy "$PAYLOAD/browser/edge/Default/Bookmarks"   "$HOME/Library/Application Support/Microsoft Edge/Default/Bookmarks"
  backup_then_copy "$PAYLOAD/browser/safari/Bookmarks.plist"   "$HOME/Library/Safari/Bookmarks.plist"

  [ -f "$MANIFEST/chrome-extension-ids.txt" ] && \
    log "  Chrome extension IDs are listed in manifest/chrome-extension-ids.txt (reinstall via sign-in or the Web Store)."
}

# ----------------------------------------------------------------------------
# PHASE: fonts
# ----------------------------------------------------------------------------
phase_fonts() {
  should_run fonts || return 0
  section "Fonts"
  [ -d "$PAYLOAD/fonts/Fonts" ] || { log "No fonts captured; skipping."; return 0; }
  confirm "Install captured user fonts?" || { log "Skipped."; return 0; }
  mkdir -p "$HOME/Library/Fonts"
  local f
  for f in "$PAYLOAD"/fonts/Fonts/*; do
    [ -e "$f" ] && backup_then_copy "$f" "$HOME/Library/Fonts/$(basename "$f")"
  done
}

# ----------------------------------------------------------------------------
# PHASE: secrets (mount encrypted DMG, restore, fix permissions)
# ----------------------------------------------------------------------------
phase_secrets() {
  should_run secrets || return 0
  section "Secrets (encrypted bundle)"
  local dmg="$SECRETS_DIR/secrets.dmg"
  [ -f "$dmg" ] || { log "No secrets bundle found; skipping."; return 0; }
  confirm "Mount the encrypted secrets bundle and restore keys/credentials?" || { log "Skipped."; return 0; }

  if [ "$DRY_RUN" = "1" ]; then
    log "  DRY: would mount $dmg and copy SSH/GPG/credentials into \$HOME, then fix permissions."
    return 0
  fi

  printf 'Passphrase for secrets bundle: '
  stty -echo 2>/dev/null; local pw; read -r pw; stty echo 2>/dev/null; printf '\n'

  local mnt="/Volumes/MigrationSecrets"
  if ! printf '%s' "$pw" | hdiutil attach "$dmg" -stdinpass -mountpoint "$mnt" -nobrowse >>"$LOG" 2>&1; then
    warn "  Could not mount the bundle (wrong passphrase?). Aborting secrets phase."
    return 1
  fi

  log "  Mounted. Copying secret material into your home folder..."
  # The bundle preserves paths relative to the old home (e.g. .ssh, .gnupg, .aws).
  local item base
  for item in "$mnt"/.* "$mnt"/*; do
    base="$(basename "$item")"
    case "$base" in .|..) continue;; esac
    [ -e "$item" ] || continue
    backup_then_copy "$item" "$HOME/$base"
  done

  hdiutil detach "$mnt" >>"$LOG" 2>&1 || warn "  Could not detach $mnt; eject it manually."

  log "  Fixing permissions..."
  if [ -d "$HOME/.ssh" ]; then
    chmod 700 "$HOME/.ssh"
    find "$HOME/.ssh" -type f ! -name '*.pub' -exec chmod 600 {} \; 2>/dev/null
    find "$HOME/.ssh" -type f -name '*.pub' -exec chmod 644 {} \; 2>/dev/null
  fi
  if [ -d "$HOME/.gnupg" ]; then
    chmod 700 "$HOME/.gnupg"
    find "$HOME/.gnupg" -type d -exec chmod 700 {} \; 2>/dev/null
    find "$HOME/.gnupg" -type f -exec chmod 600 {} \; 2>/dev/null
  fi
  [ -f "$HOME/.netrc" ] && chmod 600 "$HOME/.netrc"
  log "  Secrets restored. Verify with: ssh-add -l   and   gpg --list-secret-keys"
}

# ----------------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------------
main() {
  log "Migration restore started $(date)"
  log "Source base: $BASE"
  [ "$DRY_RUN" = "1" ] && log "*** DRY RUN: no changes will be made ***"
  log "Backups of overwritten files go to: $BACKUP"

  phase_brew
  phase_dotfiles
  phase_config
  phase_editors
  phase_apps
  phase_macos
  phase_browser
  phase_fonts
  phase_secrets

  section "Done"
  log "Restore complete. Review the manual checklist in RUNBOOK.md:"
  log "  - Grant Full Disk Access / Accessibility / Screen Recording per app"
  log "  - Sign into apps and re-enter license keys"
  log "  - Open a fresh terminal so shell + brew changes take effect"
  log "Full log: $LOG"
  [ "$DRY_RUN" != "1" ] && log "Overwritten originals backed up in: $BACKUP"
}

main "$@"
