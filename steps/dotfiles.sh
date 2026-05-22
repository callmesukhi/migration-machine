#!/usr/bin/env bash
# Step: clone the dotfiles repo (with submodules) and run its installer.
# Repo, clone path, and installer command come from the manifest config.
set -o pipefail

repo="${CFG_DOTFILESREPO:-}"
dest="$HOME/${CFG_DOTFILESCLONEDIR:-dotfiles}"
installer="${CFG_DOTFILESINSTALL:-./install.sh}"

[ -n "$repo" ] || { echo "config.dotfilesRepo is empty; nothing to clone."; exit 0; }

# Make brew available for installers that call it (no-op if not present).
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -x /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

mkdir -p "$(dirname "$dest")"

if [ -d "$dest/.git" ]; then
  echo "Repo present at $dest; pulling ..."
  GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
    git -C "$dest" pull --recurse-submodules || echo "WARN: pull failed; using existing checkout."
else
  echo "Cloning $repo -> $dest ..."
  GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
    git clone --recurse-submodules "$repo" "$dest" || { echo "ERROR: clone failed (SSH key? submodule access?)."; exit 1; }
fi

# Some dotfiles installers expect the repo symlinked at ~/.config/dotfiles.
# Harmless if yours does not use it.
mkdir -p "$HOME/.config"
ln -sfn "$dest" "$HOME/.config/dotfiles"

# Optionally stage a font zip that some installers unzip during setup, so a
# missing-file reference does not error. Set config.commitMonoUrl to enable.
if [ -n "${CFG_COMMITMONOURL:-}" ]; then
  echo "Staging CommitMono.zip ..."
  curl -fsSL "$CFG_COMMITMONOURL" -o "$dest/CommitMono.zip" || echo "WARN: font download failed (non-fatal)."
fi

echo "Running installer: $installer (in $dest) ..."
cd "$dest" || exit 1
# Ensure the installer file is executable so its own shebang is honored
# (whether that is zsh, sh, or bash).
inst_file="${installer%% *}"
[ -f "$inst_file" ] && chmod +x "$inst_file" 2>/dev/null
/bin/bash -c "$installer"
