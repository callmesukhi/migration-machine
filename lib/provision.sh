#!/usr/bin/env bash
#
# provision.sh - the migration machine orchestrator.
#
# Reads a JSON manifest (config + steps), runs each step with validation
# skip/confirm, honors required vs optional, and renders progress via the UI
# layer (swiftDialog or CLI). Run this ON THE NEW MAC, as yourself.
#
# Usage:
#   bash provision.sh --manifest homebrew            # run the homebrew manifest
#   bash provision.sh -m macports --dry-run          # preview only
#   bash provision.sh -m homebrew --only dotfiles     # run a single step
#   bash provision.sh --list                          # list available manifests
#   MIGRATE_UI=cli bash provision.sh -m homebrew      # force CLI UI
#
set -o pipefail

# ----------------------------------------------------------------------------
# Resolve paths. This script lives in lib/; MIGRATE_ROOT is the repo root (where
# manifests/ and steps/ live). BASE is the migration DATA directory (decoupled
# from the repo), where capture.sh wrote payload/, manifest/, secrets/.
# ----------------------------------------------------------------------------
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  D="$(cd -P "$(dirname "$SOURCE")" && pwd)"; SOURCE="$(readlink "$SOURCE")"
  [ "${SOURCE#/}" = "$SOURCE" ] && SOURCE="$D/$SOURCE"
done
LIB_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
MIGRATE_ROOT="$(cd -P "$LIB_DIR/.." && pwd)"
KIT_DIR="$MIGRATE_ROOT"                      # manifests/ and steps/ live at the repo root
: "${MIGRATION_DATA:=$HOME/migration-data}"
BASE="$MIGRATION_DATA"
PAYLOAD="$BASE/payload"
mkdir -p "$BASE"

STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BASE/logs"
export MIGRATE_LOG="$BASE/logs/provision-$STAMP.log"

# shellcheck disable=SC1091
. "$LIB_DIR/core.sh"
# shellcheck disable=SC1091
. "$LIB_DIR/ui.sh"

export KIT_DIR BASE PAYLOAD MIGRATE_ROOT MIGRATION_DATA

# ----------------------------------------------------------------------------
# Args
# ----------------------------------------------------------------------------
MANIFEST=""
ONLY=""
DRY_RUN=0

list_manifests() {
  echo "Available manifests in $KIT_DIR/manifests:"
  local f
  for f in "$KIT_DIR"/manifests/*.json; do
    [ -e "$f" ] || continue
    echo "  - $(basename "$f" .json)"
  done
}

resolve_manifest() {
  local m="$1"
  if [ -f "$m" ]; then echo "$m"; return 0; fi
  if [ -f "$KIT_DIR/manifests/$m.json" ]; then echo "$KIT_DIR/manifests/$m.json"; return 0; fi
  if [ -f "$KIT_DIR/manifests/$m" ]; then echo "$KIT_DIR/manifests/$m"; return 0; fi
  return 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--manifest) shift; MANIFEST="$1" ;;
    --only)        shift; ONLY="$1" ;;
    --dry-run)     DRY_RUN=1 ;;
    --ui)          shift; export MIGRATE_UI="$1" ;;
    --list)        list_manifests; exit 0 ;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1"; exit 2 ;;
  esac
  shift
done

if [ -z "$MANIFEST" ]; then
  echo "No manifest specified."; echo; list_manifests
  echo; echo "Example: bash provision.sh --manifest homebrew"
  exit 2
fi

MANIFEST_FILE="$( resolve_manifest "$MANIFEST" )" || { echo "Manifest not found: $MANIFEST"; list_manifests; exit 2; }
info "Using manifest: $MANIFEST_FILE"

# ----------------------------------------------------------------------------
# Load config -> environment (CFG_*)
# ----------------------------------------------------------------------------
while IFS= read -r line; do
  [ -z "$line" ] && continue
  export "$line"
done < <( emit_config "$MANIFEST_FILE" )

# ----------------------------------------------------------------------------
# Load steps -> parallel arrays
# ----------------------------------------------------------------------------
S_ID=(); S_TITLE=(); S_SUB=(); S_RUN=(); S_VAL=(); S_REQ=()
# Fields are \x1f-separated (non-whitespace) so empty fields are preserved.
while IFS=$'\037' read -r f_id f_title f_sub f_run f_val f_req; do
  [ -z "$f_id" ] && continue
  S_ID+=("$f_id"); S_TITLE+=("$f_title"); S_SUB+=("$f_sub")
  S_RUN+=("$f_run"); S_VAL+=("$f_val"); S_REQ+=("$f_req")
done < <( emit_steps "$MANIFEST_FILE" )

n=${#S_ID[@]}
if [ "$n" -eq 0 ]; then
  echo "Manifest has no steps. Nothing to do."; exit 1
fi

# ----------------------------------------------------------------------------
# Run
# ----------------------------------------------------------------------------
ui_init "${S_TITLE[@]}"
[ "$DRY_RUN" = "1" ] && info "DRY RUN: no changes will be made"

fails=0
failed_list=""
ran=0
skipped=0

abort() {
  ui_finish "Stopped at required step: $1. See log: $MIGRATE_LOG"
  print_summary
  exit 1
}

print_summary() {
  info "Summary: ran=$ran skipped=$skipped failed=$fails [$failed_list ]"
}

i=0
while [ "$i" -lt "$n" ]; do
  idx=$((i + 1))
  id="${S_ID[$i]}"; title="${S_TITLE[$i]}"; run="${S_RUN[$i]}"; val="${S_VAL[$i]}"; req="${S_REQ[$i]}"
  i=$((i + 1))

  # --only filter
  if [ -n "$ONLY" ] && [ "$ONLY" != "$id" ]; then
    continue
  fi

  ui_step_begin "$idx" "$title"

  # Already satisfied?
  if validate "$val"; then
    ui_step_end "$idx" skip "Already set"
    info "step $id: already satisfied"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$DRY_RUN" = "1" ]; then
    ui_step_end "$idx" skip "Would run"
    continue
  fi

  # Execute the step script (inherits CFG_*, KIT_DIR, BASE, PAYLOAD).
  # Stream output to the terminal AND the log so sudo/passphrase prompts are
  # visible; PIPESTATUS[0] gives the step's real exit code, not tee's.
  info "step $id: running $run"
  STEP_ID="$id" /bin/bash "$KIT_DIR/$run" 2>&1 | tee -a "$MIGRATE_LOG"
  step_rc=${PIPESTATUS[0]}
  if [ "$step_rc" -eq 0 ]; then
    ran=$((ran + 1))
    if [ -n "$val" ] && ! validate "$val"; then
      ui_step_end "$idx" warn "Ran, but did not validate"
      warn "step $id ran but validation still fails"
      failed_list="$failed_list $id"; fails=$((fails + 1))
      [ "$req" = "1" ] && abort "$title"
    else
      ui_step_end "$idx" success "Done"
    fi
  else
    err "step $id failed (rc=$step_rc)"
    failed_list="$failed_list $id"; fails=$((fails + 1))
    if [ "$req" = "1" ]; then
      ui_step_end "$idx" fail "Failed (required)"
      abort "$title"
    else
      ui_step_end "$idx" warn "Failed (optional), continuing"
    fi
  fi
done

if [ "$fails" -eq 0 ]; then
  ui_finish "All done. Open a fresh terminal, then finish the manual checklist in the README."
else
  ui_finish "Finished with $fails issue(s):$failed_list . See log: $MIGRATE_LOG"
fi
print_summary
exit 0
