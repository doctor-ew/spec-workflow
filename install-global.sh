#!/usr/bin/env bash
# install-global.sh — install all workflow commands into ~/.claude/commands/
#
# Commands are global — they work in every repo without per-repo setup.
# Hooks and agents still need per-repo install (use install.sh for that).
#
# Run once per machine after cloning, or re-run to update.
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

echo "🌐 Installing all workflow commands to ~/.claude/commands/"
echo ""

INSTALLED=0
SKIPPED=0

for f in "$SRC"/*.md; do
  name="$(basename "$f")"
  if [ -f "$DST/$name" ]; then
    # Silently overwrite if content differs — this is an update run
    if ! diff -q "$f" "$DST/$name" > /dev/null 2>&1; then
      cp "$f" "$DST/$name"
      echo "   ↑ updated  /$( basename "$name" .md )"
      INSTALLED=$((INSTALLED + 1))
    else
      SKIPPED=$((SKIPPED + 1))
    fi
  else
    cp "$f" "$DST/$name"
    echo "   ✓ installed /$( basename "$name" .md )"
    INSTALLED=$((INSTALLED + 1))
  fi
done

echo ""
echo "✅ Done — $INSTALLED installed/updated, $SKIPPED already current."
echo ""
echo "   Harness:  /drew-product <ISSUE>  /drew-eng <ISSUE>"
echo "   Workflow: /spec  /implement  /review  /preflight  /investigate"
echo "   Utils:    /review-spec  /unit-tests  /merge-conflicts  /propagate-fix"
