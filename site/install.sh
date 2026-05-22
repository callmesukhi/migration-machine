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
TARBALL="https://github.com/$REPO/archive/refs/heads/$REF.tar.gz"
case "$REF" in v[0-9]*) TARBALL="https://github.com/$REPO/archive/refs/tags/$REF.tar.gz" ;; esac

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

mkdir -p "$DEST"
# The archive nests everything under <repo>-<ref>/; strip that one level.
tar -xzf "$tmp/mm.tar.gz" -C "$DEST" --strip-components=1 || die "extract failed."
[ -f "$DEST/migrate" ] || die "install looks incomplete (no migrate at $DEST/migrate)."

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
