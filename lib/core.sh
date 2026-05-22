#!/usr/bin/env bash
#
# core.sh - shared helpers for the migration machine.
# Sourced by provision.sh and (indirectly) by step scripts via the environment.
#
# macOS bash 3.2 compatible. No associative arrays, no mapfile.

# ----------------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------------
# Expects MIGRATE_LOG to be set by the caller; falls back to a temp file.
: "${MIGRATE_LOG:=/tmp/migrate-machine.log}"

log()  { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$MIGRATE_LOG"; }
info() { log "INFO  $*"; }
warn() { log "WARN  $*"; }
err()  { log "ERROR $*"; }

# ----------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Is a real GUI console session present for the current user?
gui_session() {
  has_cmd /usr/sbin/scutil || return 1
  local console
  console=$( echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil 2>/dev/null | awk '/Name :/ { print $3 }' )
  [ -n "$console" ] && [ "$console" != "loginwindow" ] && [ "$console" = "$(id -un)" ]
}

# Run a validation expression. Empty expression => "no validation" => return 1
# (i.e. "not already satisfied", so the step will run).
validate() {
  local expr="$1"
  [ -z "$expr" ] && return 1
  /bin/bash -c "$expr" >/dev/null 2>&1
}

# ----------------------------------------------------------------------------
# Manifest parsing
# ----------------------------------------------------------------------------
# Two emitters, each tries python3 first (fast, also used in CI/tests), then
# falls back to JavaScriptCore via osascript, which exists on a stock Mac even
# before the Command Line Tools are installed.

# emit_config <manifest> -> lines "CFG_<UPPERKEY>=value"
emit_config() {
  local manifest="$1"
  if has_cmd python3; then
    MANIFEST="$manifest" python3 - "$manifest" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k, v in (d.get("config") or {}).items():
    print("CFG_%s=%s" % (k.upper(), v))
PY
  elif has_cmd osascript; then
    /usr/bin/osascript -l JavaScript -e '
      function run(argv){
        var app = Application.currentApplication(); app.includeStandardAdditions = true;
        var d = JSON.parse(app.read(Path(argv[0])));
        var c = d.config || {}; var out = [];
        Object.keys(c).forEach(function(k){ out.push("CFG_" + k.toUpperCase() + "=" + c[k]); });
        return out.join("\n");
      }' "$manifest"
  else
    err "No JSON parser available (need python3 or osascript)."
    return 1
  fi
}

# emit_steps <manifest> -> one line per step, fields separated by ASCII Unit
# Separator (\x1f): id, title, subtitle, run, validation, required(0/1).
# A non-whitespace separator is required so that empty fields (e.g. blank
# subtitle or validation) are preserved by `read` instead of being collapsed.
emit_steps() {
  local manifest="$1"
  if has_cmd python3; then
    python3 - "$manifest" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
def clean(x): return str(x).replace("\t", " ").replace("\n", " ").replace("\x1f", " ")
for s in (d.get("steps") or []):
    row = [clean(s.get(k, "")) for k in ("id", "title", "subtitle", "run", "validation")]
    row.append("1" if s.get("required") else "0")
    print("\x1f".join(row))
PY
  elif has_cmd osascript; then
    /usr/bin/osascript -l JavaScript -e '
      function run(argv){
        var app = Application.currentApplication(); app.includeStandardAdditions = true;
        var d = JSON.parse(app.read(Path(argv[0])));
        function clean(x){ return (x == null ? "" : x.toString()).replace(/\t/g," ").replace(/\n/g," ").replace(/\x1f/g," "); }
        var out = [];
        (d.steps || []).forEach(function(s){
          var row = ["id","title","subtitle","run","validation"].map(function(k){ return clean(s[k]); });
          row.push(s.required ? "1" : "0");
          out.push(row.join("\x1f"));
        });
        return out.join("\n");
      }' "$manifest"
  else
    err "No JSON parser available (need python3 or osascript)."
    return 1
  fi
}
