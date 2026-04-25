#!/usr/bin/env bash
# install.sh — install spec-workflow into any repo
#
# Usage:
#   ./install.sh                      # install into current directory
#   ./install.sh /path/to/target-repo # install into specified directory
#
# What it installs:
#   .claude/hooks/     — spec-guardrail, check-scope, pr-guardrail, workflow-reminder
#   .claude/agents/    — spec-writer, architect, engineer, qa, code-reviewer, + more
#   .claude/commands/  — /spec, /implement, /review, /review-spec, /preflight, /investigate
#   .claude/settings.json — wires all hooks (SessionStart, PreToolUse, PostToolUse)
#
#   ~/.claude/commands/ — /drew-product and /drew-eng (global harness commands, optional)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$(pwd)}"

if [ ! -d "$TARGET" ]; then
  echo "❌ Target directory not found: $TARGET"
  exit 1
fi

echo "📦 Installing spec-workflow into: $TARGET"
echo ""

# ── Per-repo install ────────────────────────────────────────────────────────

SKIP_SETTINGS=""

if [ -f "$TARGET/.claude/settings.json" ]; then
  read -r -p "⚠️  .claude/settings.json already exists. Overwrite? [y/N] " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Skipping settings.json — all other files will still be copied."
    rsync -a \
      --exclude='settings.json' \
      --exclude='settings.local.json' \
      --exclude='global-commands' \
      "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
    chmod +x "$TARGET/.claude/hooks/"*.sh 2>/dev/null || true
    echo "✅ Done (settings.json preserved)"
    SKIP_SETTINGS=1
  fi
fi

if [ -z "$SKIP_SETTINGS" ]; then
  rsync -a \
    --exclude='settings.local.json' \
    --exclude='global-commands' \
    "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
  chmod +x "$TARGET/.claude/hooks/"*.sh 2>/dev/null || true
  echo "✅ Per-repo install complete: $TARGET/.claude/"
fi

echo ""

# ── Global commands (/drew-product + /drew-eng) ────────────────────────────

GLOBAL_CMDS_SRC="$SCRIPT_DIR/.claude/global-commands"
GLOBAL_CMDS_DST="$HOME/.claude/commands"

if [ -d "$GLOBAL_CMDS_SRC" ] && [ "$(ls -A "$GLOBAL_CMDS_SRC" 2>/dev/null)" ]; then
  echo "🌐 Global commands available: $(ls "$GLOBAL_CMDS_SRC" | tr '\n' ' ')"
  read -r -p "   Install to ~/.claude/commands/ (available in ALL repos)? [Y/n] " gconfirm
  if [[ "$gconfirm" != "n" && "$gconfirm" != "N" ]]; then
    mkdir -p "$GLOBAL_CMDS_DST"
    for f in "$GLOBAL_CMDS_SRC"/*.md; do
      name="$(basename "$f")"
      if [ -f "$GLOBAL_CMDS_DST/$name" ]; then
        read -r -p "   ~/.claude/commands/$name already exists. Overwrite? [y/N] " oconfirm
        if [[ "$oconfirm" != "y" && "$oconfirm" != "Y" ]]; then
          echo "   Skipped $name"
          continue
        fi
      fi
      cp "$f" "$GLOBAL_CMDS_DST/$name"
      echo "   ✓ $name → ~/.claude/commands/"
    done
    echo "✅ Global commands installed."
  else
    echo "   Skipped. To install later:"
    echo "   cp $GLOBAL_CMDS_SRC/*.md ~/.claude/commands/"
  fi
fi

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  spec-workflow installed"
echo ""
echo "  Per-repo commands: /spec · /implement · /review · /preflight"
echo "  Global commands:   /drew-product · /drew-eng  (if installed above)"
echo ""
echo "  Harness flow:"
echo "    /drew-product <ISSUE>   fetch/create GH Issue → grounding Qs → /spec"
echo "    /drew-eng <ISSUE>       adversarial claim verify + DRY/SOLID/Big O review"
echo "    /implement <ISSUE> build from approved spec"
echo ""
echo "  SPEC GUARDRAIL active: SPEC*.md writes blocked without"
echo "    ## Sources (path:line + commit SHA) and ## Model Router (filled Decision)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
