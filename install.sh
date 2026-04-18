#!/usr/bin/env bash
# install.sh — install spec-workflow into any repo
# Usage: ./install.sh [/path/to/target-repo]
#        (defaults to current directory)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$(pwd)}"

if [ ! -d "$TARGET" ]; then
  echo "❌ Target directory not found: $TARGET"
  exit 1
fi

echo "📦 Installing spec-workflow into: $TARGET"

# Check for existing settings.json
if [ -f "$TARGET/.claude/settings.json" ]; then
  read -r -p "⚠️  .claude/settings.json already exists. Overwrite? [y/N] " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Skipping settings.json — all other files will still be copied."
    rsync -a --exclude='settings.json' --exclude='settings.local.json' \
      "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
    echo "✅ Done (settings.json preserved)"
    exit 0
  fi
fi

rsync -a --exclude='settings.local.json' "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"

# Make hooks executable
chmod +x "$TARGET/.claude/hooks/"*.sh 2>/dev/null || true

echo "✅ Installed into $TARGET/.claude/"
echo ""
echo "Available commands: /spec · /implement · /review · /review-spec · /preflight · /investigate"
echo "Agents: spec-writer · architect · engineer · qa · code-reviewer · security-auditor · preflight"
