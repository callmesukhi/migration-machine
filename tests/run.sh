#!/usr/bin/env bash
#
# tests/run.sh - engine behavior tests for migration-machine.
#
# Validates the orchestrator's control flow with fake step scripts. No real
# macOS commands are exercised, so this runs anywhere (Linux CI or macOS).
# Exits non-zero if any assertion fails.
#
set -u

SOURCE="${BASH_SOURCE[0]}"
TESTS_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
REPO="$(cd -P "$TESTS_DIR/.." && pwd)"
FIX="tests/fixtures"

pass=0
fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }

newtmp() {
  DATA="$(mktemp -d)"
  MARKER_DIR="$(mktemp -d)"
  export MARKER_DIR
}

run_provision() {
  MIGRATE_UI=cli bash "$REPO/migrate" --data "$DATA" provision "$@"
}

# --- parser: empty fields preserved (6 \x1f-separated columns) ---
# shellcheck disable=SC1091
. "$REPO/lib/core.sh"
nfields="$(emit_steps "$REPO/$FIX/test-ok.json" | head -1 | awk -F'\037' '{print NF}')"
[ "$nfields" = "6" ] && ok "parser preserves 6 fields (got $nfields)" || no "parser fields=$nfields, want 6"

# --- Scenario 1: normal run ---
newtmp
run_provision -m "$REPO/$FIX/test-ok.json" >/tmp/_mm_s1 2>&1
rc=$?
[ $rc -eq 0 ] && ok "S1 exit 0" || no "S1 exit $rc"
[ -f "$MARKER_DIR/ran_stepA" ] && ok "S1 stepA ran" || no "S1 stepA did not run"
[ ! -f "$MARKER_DIR/ran_stepB" ] && ok "S1 stepB skipped by validation" || no "S1 stepB ran (should skip)"
[ -f "$MARKER_DIR/cmarker" ] && ok "S1 stepC ran and validated" || no "S1 stepC failed"
[ -f "$MARKER_DIR/ran_stepD" ] && ok "S1 stepD ran then failed (optional)" || no "S1 stepD did not run"

# --- Scenario 2: dry-run changes nothing ---
newtmp
run_provision -m "$REPO/$FIX/test-ok.json" --dry-run >/tmp/_mm_s2 2>&1
rc=$?
[ $rc -eq 0 ] && ok "S2 dry-run exit 0" || no "S2 dry-run exit $rc"
if ls "$MARKER_DIR"/* >/dev/null 2>&1; then no "S2 dry-run created files"; else ok "S2 dry-run inert"; fi

# --- Scenario 3: --only runs a single step ---
newtmp
run_provision -m "$REPO/$FIX/test-ok.json" --only stepC >/tmp/_mm_s3 2>&1
{ [ -f "$MARKER_DIR/cmarker" ] && [ ! -f "$MARKER_DIR/ran_stepA" ]; } \
  && ok "S3 --only ran just stepC" || no "S3 --only did not isolate stepC"

# --- Scenario 4: required failure aborts the run ---
newtmp
run_provision -m "$REPO/$FIX/test-req.json" >/tmp/_mm_s4 2>&1
rc=$?
[ $rc -eq 1 ] && ok "S4 exit 1 on required failure" || no "S4 exit $rc (want 1)"
[ -f "$MARKER_DIR/ran_stepA2" ] && ok "S4 stepA2 ran" || no "S4 stepA2 did not run"
[ -f "$MARKER_DIR/ran_stepE" ] && ok "S4 stepE ran" || no "S4 stepE did not run"
[ ! -f "$MARKER_DIR/ran_stepF" ] && ok "S4 stepF skipped (aborted)" || no "S4 stepF ran after abort"
grep -q 'Stopped at required step' /tmp/_mm_s4 && ok "S4 abort message shown" || no "S4 no abort message"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
