#!/usr/bin/env bash
#
# bootstrap.sh - bare-Mac entrypoint (invoked as `migrate bootstrap`).
# Ensures the Xcode Command Line Tools (git + python3) exist, then provisions.
# All arguments pass through to provision.
#
set -o pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  D="$(cd -P "$(dirname "$SOURCE")" && pwd)"; SOURCE="$(readlink "$SOURCE")"
  [ "${SOURCE#/}" = "$SOURCE" ] && SOURCE="$D/$SOURCE"
done
LIB_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

echo "==> Ensuring Xcode Command Line Tools (git, python3) ..."
if /usr/bin/xcode-select -p >/dev/null 2>&1; then
  echo "    Already installed."
else
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  label="$(softwareupdate -l 2>/dev/null \
    | grep -E 'Label: Command Line Tools' \
    | sed -e 's/^.*Label: //' \
    | sort -V | tail -n1)"
  if [ -n "$label" ]; then
    echo "    Installing: $label"
    sudo softwareupdate -i "$label" --verbose || true
  else
    echo "    Falling back to the GUI installer prompt; complete it, then re-run."
    xcode-select --install 2>/dev/null || true
  fi
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    echo "ERROR: Command Line Tools not present yet. Finish the install and re-run." >&2
    exit 1
  fi
fi

echo "==> Handing off to provision ..."
exec /bin/bash "$LIB_DIR/provision.sh" "$@"
