#!/usr/bin/env bash
#
# ui.sh - progress UI abstraction for the migration machine.
#
# Two backends:
#   cli  - clean terminal output with per-step status (always works, testable)
#   gui  - swiftDialog list with live status (when a GUI session + dialog exist)
#
# Auto-detection picks gui only when it will actually work, else cli.
# Override with MIGRATE_UI=cli|gui|auto (default auto).
#
# Public API (1-based step indexes):
#   ui_init "Title 1" "Title 2" ...
#   ui_step_begin <index> <title>
#   ui_step_end   <index> <success|fail|skip|warn> <text>
#   ui_finish     <message>

DIALOG_BIN="${DIALOG_BIN:-/usr/local/bin/dialog}"
UI_CMDFILE="${UI_CMDFILE:-/var/tmp/migrate-dialog.log}"

ui_detect_mode() {
  case "${MIGRATE_UI:-auto}" in
    cli) UI_MODE="cli" ;;
    gui) UI_MODE="gui" ;;
    *)
      if [ -x "$DIALOG_BIN" ] && [ -z "${SSH_TTY:-}" ] && gui_session; then
        UI_MODE="gui"
      else
        UI_MODE="cli"
      fi
      ;;
  esac
  # If gui was requested/chosen but the binary is missing, degrade gracefully.
  if [ "$UI_MODE" = "gui" ] && [ ! -x "$DIALOG_BIN" ]; then
    UI_MODE="cli"
  fi
}

# ----------------------------------------------------------------------------
ui_init() {
  UI_TITLES=( "$@" )
  UI_TOTAL=$#
  ui_detect_mode
  if [ "$UI_MODE" = "gui" ]; then
    _ui_gui_init
  else
    _ui_cli_init
  fi
}

ui_step_begin() {
  if [ "$UI_MODE" = "gui" ]; then _ui_gui_begin "$1" "$2"; else _ui_cli_begin "$1" "$2"; fi
}

ui_step_end() {
  if [ "$UI_MODE" = "gui" ]; then _ui_gui_end "$1" "$2" "$3"; else _ui_cli_end "$1" "$2" "$3"; fi
}

ui_finish() {
  if [ "$UI_MODE" = "gui" ]; then _ui_gui_finish "$1"; else _ui_cli_finish "$1"; fi
}

# ----------------------------------------------------------------------------
# CLI backend
# ----------------------------------------------------------------------------
_ui_cli_init() {
  if [ -t 1 ]; then
    C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_RST=$'\033[0m'
  else
    C_GREEN=""; C_RED=""; C_YEL=""; C_DIM=""; C_BOLD=""; C_RST=""
  fi
  printf '\n%sMigration Machine%s  (%d steps)\n' "$C_BOLD" "$C_RST" "$UI_TOTAL"
  printf '%sLog: %s%s\n\n' "$C_DIM" "$MIGRATE_LOG" "$C_RST"
}

_ui_cli_begin() {
  printf '%s%s[%d/%d] %s%s\n' "$C_BOLD" "$C_DIM" "$1" "$UI_TOTAL" "$2" "$C_RST"
}

_ui_cli_end() {
  local status="$2" text="$3" sym col
  case "$status" in
    success) sym="ok";   col="$C_GREEN" ;;
    skip)    sym="skip"; col="$C_DIM" ;;
    warn)    sym="warn"; col="$C_YEL" ;;
    fail)    sym="FAIL"; col="$C_RED" ;;
    *)       sym="$status"; col="" ;;
  esac
  printf '      %s[%s]%s %s\n' "$col" "$sym" "$C_RST" "$text"
}

_ui_cli_finish() {
  printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RST"
}

# ----------------------------------------------------------------------------
# swiftDialog backend (command-file protocol; dialog uses 0-based list indexes)
# ----------------------------------------------------------------------------
_ui_gui_init() {
  : > "$UI_CMDFILE"
  chmod 666 "$UI_CMDFILE" 2>/dev/null
  local listargs=() t
  for t in "${UI_TITLES[@]}"; do listargs+=( --listitem "$t" ); done
  "$DIALOG_BIN" \
    --title "Migration Machine" \
    --message "Setting up your Mac. You can watch progress here." \
    --icon "SF=desktopcomputer.and.arrow.down" \
    --progress "$UI_TOTAL" \
    --commandfile "$UI_CMDFILE" \
    --button1text "Please wait" --button1disabled \
    --moveable --ontop \
    "${listargs[@]}" >/dev/null 2>&1 &
  UI_DIALOG_PID=$!
  sleep 1
}

_ui_gui_begin() {
  local i=$(( $1 - 1 ))
  {
    echo "listitem: index: $i, status: wait, statustext: Working…"
    echo "progress: $i"
    echo "progresstext: $2"
  } >> "$UI_CMDFILE"
}

_ui_gui_end() {
  local i=$(( $1 - 1 )) dstatus
  case "$2" in
    success) dstatus="success" ;;
    skip)    dstatus="success" ;;
    warn)    dstatus="error" ;;
    fail)    dstatus="fail" ;;
    *)       dstatus="pending" ;;
  esac
  {
    echo "listitem: index: $i, status: $dstatus, statustext: $3"
    echo "progress: $1"
  } >> "$UI_CMDFILE"
}

_ui_gui_finish() {
  {
    echo "progresstext: $1"
    echo "progress: complete"
    echo "button1text: Done"
    echo "button1: enable"
  } >> "$UI_CMDFILE"
}
