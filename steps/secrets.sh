#!/usr/bin/env bash
# Step: restore SSH/GPG keys and credentials from the encrypted bundle.
# Delegates to the verified restore command (single source of truth).
# You will be prompted once for the bundle passphrase, so run from a terminal.
set -o pipefail

if [ ! -x "$MIGRATE_ROOT/migrate" ]; then
  echo "migrate entrypoint not found at $MIGRATE_ROOT; cannot restore secrets."
  exit 1
fi

dmg="$MIGRATION_DATA/${CFG_SECRETSDMG:-secrets/secrets.dmg}"
if [ ! -f "$dmg" ]; then
  echo "No secrets bundle at $dmg."
  echo "Either run 'migrate capture' on the old Mac, or skip this step if you carry keys another way."
  exit 0
fi

echo "Restoring secrets (you will be asked for the passphrase) ..."
"$MIGRATE_ROOT/migrate" restore --yes --only secrets
