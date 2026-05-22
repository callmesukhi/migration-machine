#!/usr/bin/env bash
# Step: enable TouchID authentication for sudo (boblbee-inspired).
# Uses /etc/pam.d/sudo_local on macOS 14+ (survives OS updates); edits
# /etc/pam.d/sudo on older releases. Idempotent.
set -o pipefail

if grep -q pam_tid /etc/pam.d/sudo_local 2>/dev/null || grep -q pam_tid /etc/pam.d/sudo 2>/dev/null; then
  echo "TouchID for sudo already enabled."
  exit 0
fi

major="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"
[ -z "$major" ] && major=0

if [ "$major" -ge 14 ]; then
  echo "Enabling via /etc/pam.d/sudo_local (macOS $major) ..."
  printf 'auth       sufficient     pam_tid.so\n' | sudo tee /etc/pam.d/sudo_local >/dev/null
else
  echo "Enabling via /etc/pam.d/sudo (macOS $major) ..."
  sudo sed -i '' '2i\
auth       sufficient     pam_tid.so
' /etc/pam.d/sudo
fi

grep -q pam_tid /etc/pam.d/sudo_local 2>/dev/null || grep -q pam_tid /etc/pam.d/sudo 2>/dev/null
