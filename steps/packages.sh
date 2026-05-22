#!/usr/bin/env bash
# Step: install packages/apps from the captured list.
#   brew -> Brewfile (formulae, casks, mas apps)
#   port -> a plain port list, one port per line
set -o pipefail

case "${CFG_PACKAGEMANAGER:-brew}" in
  brew)
    bf="$BASE/${CFG_BREWFILE:-manifest/Brewfile}"
    if [ ! -f "$bf" ]; then
      echo "No Brewfile at $bf; nothing to install. (Run capture.sh on the old Mac first.)"
      exit 0
    fi
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [ -x /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"
    command -v brew >/dev/null 2>&1 || { echo "brew not on PATH; run the package-manager step first."; exit 1; }
    echo "Running brew bundle (this can take a while) ..."
    brew bundle install --file="$bf"
    ;;

  port)
    pf="$BASE/${CFG_PORTFILE:-manifest/portfile.txt}"
    if [ ! -f "$pf" ]; then
      echo "No port list at $pf; nothing to install."
      echo "Create it with one port name per line (\# comments allowed)."
      exit 0
    fi
    ports="$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$pf" | tr '\n' ' ')"
    if [ -n "$ports" ]; then
      echo "Installing ports: $ports"
      # shellcheck disable=SC2086
      sudo /opt/local/bin/port -N install $ports
    else
      echo "Port list is empty."
    fi
    ;;

  *)
    echo "Unknown packageManager: ${CFG_PACKAGEMANAGER:-}"
    exit 1
    ;;
esac
