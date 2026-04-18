#!/usr/bin/env bash
# install-global.sh — install /drprod and /dreng into ~/.claude/commands/
#
# These are session harness commands that work across ALL repos.
# Run this once per machine, separate from per-repo install.sh.
#
# Usage: ./install-global.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/.claude/global-commands"
DST="$HOME/.claude/commands"

if [ ! -d "$SRC" ] || [ -z "$(ls -A "$SRC" 2>/dev/null)" ]; then
  echo "❌ No global commands found at $SRC"
  exit 1
fi

mkdir -p "$DST"

echo "🌐 Installing global commands to ~/.claude/commands/"
echo ""

for f in "$SRC"/*.md; do
  name="$(basename "$f")"
  if [ -f "$DST/$name" ]; then
    read -r -p "   $name already exists. Overwrite? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo "   Skipped $name"
      continue
    fi
  fi
  cp "$f" "$DST/$name"
  echo "   ✓ /$( basename "$name" .md ) → ~/.claude/commands/"
done

echo ""
echo "✅ Done. Available in every repo (no --add-dir needed):"
echo ""
echo "   /drprod <ISSUE>   — fetch/create GitHub Issue → grounding Qs → /spec"
echo "   /dreng  <ISSUE>   — adversarial claim verify → /implement"
