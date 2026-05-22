#!/usr/bin/env bash
# Step: apply captured macOS system defaults.
# Delegates to the verified restore macos phase, then optionally runs an
# extra defaults script named by config.extraDefaults (boblbee-style).
set -o pipefail

if [ -x "$MIGRATE_ROOT/migrate" ]; then
  echo "Importing captured macOS defaults ..."
  "$MIGRATE_ROOT/migrate" restore --yes --only macos || echo "WARN: macos defaults import reported issues."
else
  echo "migrate entrypoint not found at $MIGRATE_ROOT; skipping captured defaults."
fi

if [ -n "${CFG_EXTRADEFAULTS:-}" ] && [ -f "$MIGRATION_DATA/$CFG_EXTRADEFAULTS" ]; then
  echo "Running extra defaults script: $CFG_EXTRADEFAULTS ..."
  /bin/bash "$MIGRATION_DATA/$CFG_EXTRADEFAULTS" || echo "WARN: extra defaults script reported issues."
fi

# Apply some changes immediately.
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
echo "Done. Some settings take effect after logout/restart."
