#!/usr/bin/env bash
# Step: Xcode Command Line Tools (idempotent).
set -o pipefail

if /usr/bin/xcode-select -p >/dev/null 2>&1; then
  echo "Command Line Tools already installed."
  exit 0
fi

echo "Installing Command Line Tools ..."
touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
label="$(softwareupdate -l 2>/dev/null \
  | grep -E 'Label: Command Line Tools' \
  | sed -e 's/^.*Label: //' \
  | sort -V | tail -n1)"
if [ -n "$label" ]; then
  echo "  via softwareupdate: $label"
  sudo softwareupdate -i "$label" --verbose || true
else
  echo "  via GUI prompt (complete it, then re-run this step)"
  xcode-select --install 2>/dev/null || true
fi
rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

/usr/bin/xcode-select -p >/dev/null 2>&1
