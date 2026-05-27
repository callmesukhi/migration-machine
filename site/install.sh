#!/bin/sh
#
# migration-machine installer.
#
# One line, no git or Xcode tools needed up front:
#   curl -fsSL https://migration-machine.callmesukhi.com/install.sh | bash
#
# It downloads migration-machine into ~/.migration-machine and launches the
# guided setup (swiftDialog). In keeping with the project's "read it before you
# run it" idea, you are encouraged to inspect this first:
#   curl -fsSL https://migration-machine.callmesukhi.com/install.sh -o install.sh
#   less install.sh
#   bash install.sh
#
# Overrides (optional):
#   MIGRATION_MACHINE_REF=v0.1.0   # branch or tag to install (default: main)
#   MIGRATION_MACHINE_HOME=DIR     # where to install (default: ~/.migration-machine)
#   MM_NO_LAUNCH=1                 # download only, do not start the wizard
#
set -eu

REPO="callmesukhi/migration-machine"
REF="${MIGRATION_MACHINE_REF:-main}"
DEST="${MIGRATION_MACHINE_HOME:-$HOME/.migration-machine}"
# GitHub's bare archive endpoint resolves a branch, tag, or commit SHA, so we
# do not have to guess what kind of ref MIGRATION_MACHINE_REF is.
TARBALL="https://github.com/$REPO/archive/$REF.tar.gz"

say() { printf '\033[1m>_\033[0m %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "migration-machine is for macOS (detected $(uname -s))."
command -v curl >/dev/null 2>&1 || die "curl is required but not found."
command -v tar  >/dev/null 2>&1 || die "tar is required but not found."

say "Downloading migration-machine ($REF) into $DEST"
# BSD/macOS mktemp needs an explicit template (it is not GNU mktemp), so always
# pass one. This form works on both macOS and Linux.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/migration-machine.XXXXXX")" || die "could not create a temporary directory."
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$TARBALL" -o "$tmp/mm.tar.gz" || die "download failed: $TARBALL"

# Refuse dangerous or non-dedicated targets. Canonicalize first so trailing
# slashes or dot segments ("$HOME/", "$HOME/.", "//") cannot slip past the check.
[ -n "$DEST" ] || die "MIGRATION_MACHINE_HOME is empty."
_parent="$(cd "$(dirname "$DEST")" 2>/dev/null && pwd -P)" || die "install path's parent does not exist: $DEST"
_name="$(basename "$DEST")"
case "$_name" in
  "" | "/" | "." | "..") die "refusing to install to '$DEST'. Choose a dedicated subfolder." ;;
esac
DEST="${_parent%/}/$_name"
_home="$(cd "$HOME" 2>/dev/null && pwd -P || printf '%s' "$HOME")"
[ "$DEST" = "${_home%/}" ] && die "refusing to install to your home directory. Set MIGRATION_MACHINE_HOME to a dedicated folder."

# Extract into a staging dir, verify it, then atomically replace $DEST so a
# re-install never leaves stale files from an older version behind.
stage="$tmp/install"
mkdir -p "$stage"
# The archive nests everything under <repo>-<ref>/; strip that one level.
tar -xzf "$tmp/mm.tar.gz" -C "$stage" --strip-components=1 || die "extract failed."
[ -f "$stage/migrate" ] || die "install looks incomplete (no migrate in the downloaded archive)."
# Only replace a directory that clearly matches a prior migration-machine
# install (its real structure), never one that merely contains a file named
# "migrate". Anything else is left untouched and the install aborts.
if [ -e "$DEST" ]; then
  if [ -f "$DEST/migrate" ] && [ -f "$DEST/lib/core.sh" ] && [ -d "$DEST/steps" ] && [ -d "$DEST/manifests" ]; then
    rm -rf "$DEST"
  else
    die "$DEST already exists and does not look like a migration-machine install. Move it aside, or set MIGRATION_MACHINE_HOME to a dedicated folder."
  fi
fi
mkdir -p "$(dirname "$DEST")"
mv "$stage" "$DEST" || die "could not install to $DEST."

say "Installed to $DEST"

if [ "${MM_NO_LAUNCH:-0}" = "1" ]; then
  say "Skipping launch (MM_NO_LAUNCH=1). Start it later with:  $DEST/migrate wizard"
  exit 0
fi

# When run via `curl | bash` there is no controlling terminal, so reattach one
# so the wizard's sudo and passphrase prompts can be answered.
if [ ! -t 0 ]; then
  if [ -r /dev/tty ]; then
    exec < /dev/tty
  else
    die "an interactive Terminal is required to launch the guided setup. Run this installer from Terminal, or set MM_NO_LAUNCH=1 to install without launching."
  fi
fi

say "Launching the guided setup..."
exec /bin/bash "$DEST/migrate" wizard
