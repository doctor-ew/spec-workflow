#!/bin/bash
# pr-guardrail.sh — Hard gate on git push and gh pr create
#
# Fires on PreToolUse Bash. Detects push and PR creation commands and blocks
# until the engineer explicitly confirms: tested, target branch, and intent.
#
# Exit 0 = allow
# Exit 2 = block — output shown to Claude, which must ask engineer to confirm

INPUT=$(cat)

# python3 is required to safely parse JSON command input (regex fallback can't handle escaped quotes)
if ! command -v python3 &>/dev/null; then
  echo "PR_GUARDRAIL: python3 not found — cannot safely parse tool input. Blocking as a precaution."
  echo "Install python3 to enable this guardrail."
  exit 2
fi

COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('command', ''))
except:
    print('')
" 2>/dev/null)

# Detect git push (but not --help, --dry-run, or listing remotes)
if echo "$COMMAND" | grep -qE '\bgit push\b' && ! echo "$COMMAND" | grep -qE '(--help|--dry-run|-n\b|--list)'; then
  TARGET_BRANCH=$(echo "$COMMAND" | grep -oE 'origin [^ ]+' | awk '{print $2}' || echo "unknown")
  echo "PR_GUARDRAIL: Blocked git push."
  echo ""
  echo "Before pushing, confirm with the engineer:"
  echo "  1. Have you manually tested this code?"
  echo "  2. Target branch: ${TARGET_BRANCH:-$(git branch --show-current 2>/dev/null || echo 'unknown')}"
  echo "  3. Do you want to proceed with this push?"
  echo ""
  echo "Ask the engineer now. Do not push until they say yes."
  exit 2
fi

# Detect gh pr create
if echo "$COMMAND" | grep -qE '\bgh pr create\b'; then
  BASE_BRANCH=$(echo "$COMMAND" | grep -oE '(-B|--base) [^ ]+' | awk '{print $2}')
  echo "PR_GUARDRAIL: Blocked gh pr create."
  echo ""
  echo "Before creating a PR, confirm with the engineer:"
  echo "  1. Have you manually tested this code?"
  echo "  2. Target base branch: ${BASE_BRANCH:-not specified — confirm before proceeding}"
  echo "  3. Do you want to create this PR now?"
  echo ""
  echo "Ask the engineer now. Do not create the PR until they say yes."
  exit 2
fi

exit 0
