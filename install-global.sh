#!/usr/bin/env bash
# install-global.sh — install all workflow commands and global hooks into ~/.claude/
#
# Commands are global — they work in every repo without per-repo setup.
# Global hooks (drew-pre-tool-use, drew-post-tool-use) are installed to ~/.claude/hooks/.
# Per-repo hooks and agents still need per-repo install (use install.sh for that).
#
# Run once per machine after cloning, or re-run to update.
#
# Usage: ./install-global.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMDS_SRC="$SCRIPT_DIR/.claude/global-commands"
CMDS_DST="$HOME/.claude/commands"
HOOKS_SRC="$SCRIPT_DIR/.claude/global-hooks"
HOOKS_DST="$HOME/.claude/hooks"

if [ ! -d "$CMDS_SRC" ] || [ -z "$(ls -A "$CMDS_SRC" 2>/dev/null)" ]; then
  echo "❌ No global commands found at $CMDS_SRC"
  exit 1
fi

mkdir -p "$CMDS_DST"
mkdir -p "$HOOKS_DST"

# ── Commands ─────────────────────────────────────────────────────────────────

echo "🌐 Installing workflow commands to ~/.claude/commands/"
echo ""

INSTALLED=0
SKIPPED=0

for f in "$CMDS_SRC"/*.md; do
  name="$(basename "$f")"
  if [ -f "$CMDS_DST/$name" ]; then
    if ! diff -q "$f" "$CMDS_DST/$name" > /dev/null 2>&1; then
      cp "$f" "$CMDS_DST/$name"
      echo "   ↑ updated  /$( basename "$name" .md )"
      INSTALLED=$((INSTALLED + 1))
    else
      SKIPPED=$((SKIPPED + 1))
    fi
  else
    cp "$f" "$CMDS_DST/$name"
    echo "   ✓ installed /$( basename "$name" .md )"
    INSTALLED=$((INSTALLED + 1))
  fi
done

echo ""
echo "✅ Commands — $INSTALLED installed/updated, $SKIPPED already current."

# ── Global hooks ──────────────────────────────────────────────────────────────

if [ -d "$HOOKS_SRC" ] && [ -n "$(ls -A "$HOOKS_SRC" 2>/dev/null)" ]; then
  echo ""
  echo "🪝 Installing global hooks to ~/.claude/hooks/"
  echo ""

  HOOKS_INSTALLED=0
  HOOKS_SKIPPED=0

  for f in "$HOOKS_SRC"/*.sh; do
    name="$(basename "$f")"
    if [ -f "$HOOKS_DST/$name" ]; then
      if ! diff -q "$f" "$HOOKS_DST/$name" > /dev/null 2>&1; then
        cp "$f" "$HOOKS_DST/$name"
        chmod +x "$HOOKS_DST/$name"
        echo "   ↑ updated  $name"
        HOOKS_INSTALLED=$((HOOKS_INSTALLED + 1))
      else
        HOOKS_SKIPPED=$((HOOKS_SKIPPED + 1))
      fi
    else
      cp "$f" "$HOOKS_DST/$name"
      chmod +x "$HOOKS_DST/$name"
      echo "   ✓ installed $name"
      HOOKS_INSTALLED=$((HOOKS_INSTALLED + 1))
    fi
  done

  echo ""
  echo "✅ Hooks — $HOOKS_INSTALLED installed/updated, $HOOKS_SKIPPED already current."
fi

echo ""
echo "   Harness:  /drew-product <ISSUE>  /drew-eng <ISSUE>  /drew-qa <ISSUE>  /drew-deploy <ISSUE>"
echo "   Workflow: /spec  /implement  /review  /preflight  /investigate"
echo "   Utils:    /review-spec  /unit-tests  /merge-conflicts  /propagate-fix"
