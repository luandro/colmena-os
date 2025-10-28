#!/usr/bin/env bash
set -euo pipefail

CLAUDE_PATH="CLAUDE.md"
AGENTS_PATH="AGENTS.md"

timestamp() {
  stat -c %Y "$1"
}

copy_file() {
  src="$1"
  dest="$2"
  cp "$src" "$dest"
  echo "Synced $dest from $src"
}

if [[ ! -f $CLAUDE_PATH && ! -f $AGENTS_PATH ]]; then
  echo "Nothing to sync: neither CLAUDE.md nor AGENTS.md exists." >&2
  exit 1
fi

if [[ ! -f $AGENTS_PATH ]]; then
  copy_file "$CLAUDE_PATH" "$AGENTS_PATH"
  exit 0
fi

if [[ ! -f $CLAUDE_PATH ]]; then
  copy_file "$AGENTS_PATH" "$CLAUDE_PATH"
  exit 0
fi

if [[ $(timestamp "$CLAUDE_PATH") -gt $(timestamp "$AGENTS_PATH") ]]; then
  copy_file "$CLAUDE_PATH" "$AGENTS_PATH"
elif [[ $(timestamp "$AGENTS_PATH") -gt $(timestamp "$CLAUDE_PATH") ]]; then
  copy_file "$AGENTS_PATH" "$CLAUDE_PATH"
else
  echo "Files are already in sync."
fi
