#!/usr/bin/env bash
# Step: install the package manager named by CFG_PACKAGEMANAGER (brew | port).
set -o pipefail

case "${CFG_PACKAGEMANAGER:-brew}" in
  brew)
    if command -v brew >/dev/null 2>&1 || [ -x /opt/homebrew/bin/brew ] || [ -x /usr/local/bin/brew ]; then
      echo "Homebrew already installed."
      exit 0
    fi
    echo "Installing Homebrew (non-interactive) ..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || exit 1
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [ -x /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"
    command -v brew >/dev/null 2>&1
    ;;

  port)
    if [ -x /opt/local/bin/port ]; then
      echo "MacPorts already installed."
      exit 0
    fi
    url="${CFG_MACPORTSPKGURL:-}"
    if [ -z "$url" ]; then
      echo "ERROR: MacPorts is not installed and config.macportsPkgUrl is empty."
      echo "Pick the .pkg for your macOS version at https://www.macports.org/install.php"
      echo "and set config.macportsPkgUrl in the manifest, then re-run."
      exit 1
    fi
    echo "Downloading MacPorts installer ..."
    tmp="/tmp/MacPorts.pkg"
    curl -fsSL "$url" -o "$tmp" || exit 1
    echo "Installing MacPorts (sudo) ..."
    sudo installer -pkg "$tmp" -target / || exit 1
    rm -f "$tmp"
    [ -x /opt/local/bin/port ] && sudo /opt/local/bin/port -v selfupdate || true
    [ -x /opt/local/bin/port ]
    ;;

  *)
    echo "Unknown packageManager: ${CFG_PACKAGEMANAGER:-}"
    exit 1
    ;;
esac
