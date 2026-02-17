#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${GTR_INSTALL_DIR:-$HOME/.gtr}"
REPO_URL="https://raw.githubusercontent.com/proofofze/gtr/master/gtr.sh"

echo "Installing gtr to $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR"
curl -fsSL "$REPO_URL" -o "$INSTALL_DIR/gtr.sh"

SOURCE_LINE="source \"$INSTALL_DIR/gtr.sh\""

# Detect shell config file
if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "$SHELL")" = "zsh" ]; then
  RC_FILE="$HOME/.zshrc"
else
  RC_FILE="$HOME/.bashrc"
fi

# Add source line if not already present
if ! grep -qF "$INSTALL_DIR/gtr.sh" "$RC_FILE" 2>/dev/null; then
  printf '\n# gtr - Git worktree helper\n%s\n' "$SOURCE_LINE" >> "$RC_FILE"
  echo "Added source line to $RC_FILE"
else
  echo "Already sourced in $RC_FILE"
fi

echo "Done! Restart your shell or run: source $RC_FILE"
