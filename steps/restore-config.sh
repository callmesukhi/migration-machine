#!/usr/bin/env bash
# Step: restore captured config that your dotfiles repo does NOT own.
# Deliberately excludes the 'dotfiles' and 'config' phases so it does not fight
# the dotfiles repo (which is the source of truth for shell/git/~/.config).
# Restores: editor settings, third-party app prefs, fonts, and browser bookmarks.
set -o pipefail

if [ ! -x "$MIGRATE_ROOT/migrate" ]; then
  echo "migrate entrypoint not found at $MIGRATE_ROOT; nothing to restore."
  exit 0
fi

phases="editors apps fonts browser"
for phase in $phases; do
  echo "--- restoring: $phase ---"
  "$MIGRATE_ROOT/migrate" restore --yes --only "$phase" || echo "WARN: phase '$phase' reported issues."
done

# Non-fatal: optional config that your repo may not cover. Warnings are fine.
exit 0
