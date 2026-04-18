#!/bin/bash
# spec-guardrail.sh — Hard gate on SPEC.md writes
#
# Fires on PreToolUse Write. Blocks writing a SPEC*.md that is missing:
#   1. ## Sources with at least one verified entry (path:line + commit SHA)
#   2. ## Model Router with a filled Decision (not the template placeholder)
#
# Exit 0 = allow
# Exit 2 = block — message shown to Claude, which must fix before retrying

INPUT=$(cat)

if ! command -v python3 &>/dev/null; then
  exit 0  # can't parse tool input — allow rather than false-block
fi

FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('file_path', ''))
except:
    print('')
" 2>/dev/null)

# Only gate on SPEC*.md files
if ! echo "$FILE_PATH" | grep -qiE 'SPEC[^/]*\.md$'; then
  exit 0
fi

CONTENT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('content', ''))
except:
    print('')
" 2>/dev/null)

BLOCKED=0
MESSAGES=""

# --- Check ## Sources ---
# Must exist and have at least one real entry: `path:line` + "commit:"
HAS_SOURCES_HEADER=$(echo "$CONTENT" | grep -c "^## Sources")
SOURCES_WITH_SHA=$(echo "$CONTENT" | grep -E '`[a-zA-Z0-9_./-]+:[0-9]' | grep -c "commit:")

if [ "$HAS_SOURCES_HEADER" -eq 0 ]; then
  BLOCKED=1
  MESSAGES="$MESSAGES\n  ❌ ## Sources section is missing"
elif [ "$SOURCES_WITH_SHA" -eq 0 ]; then
  BLOCKED=1
  MESSAGES="$MESSAGES\n  ❌ ## Sources has no verified entries — each entry needs path:line, branch, and commit SHA"
fi

# --- Check ## Model Router ---
# Must exist and Decision must be filled (not the [ ] placeholder)
HAS_ROUTER_HEADER=$(echo "$CONTENT" | grep -c "^## Model Router")
ROUTER_DECISION=$(echo "$CONTENT" | grep "^\*\*Decision:\*\*" | head -1)
ROUTER_FILLED=0

if echo "$ROUTER_DECISION" | grep -qE '\*\*Decision:\*\*[[:space:]]+(Sonnet|Opus)'; then
  # Decision is filled with Sonnet or Opus (not a bracket placeholder)
  if ! echo "$ROUTER_DECISION" | grep -qE '\['; then
    ROUTER_FILLED=1
  fi
fi

if [ "$HAS_ROUTER_HEADER" -eq 0 ]; then
  BLOCKED=1
  MESSAGES="$MESSAGES\n  ❌ ## Model Router section is missing"
elif [ "$ROUTER_FILLED" -eq 0 ]; then
  BLOCKED=1
  MESSAGES="$MESSAGES\n  ❌ ## Model Router Decision is not filled in (must be 'Sonnet / General Engineer' or 'Opus / Enterprise Architect')"
fi

if [ "$BLOCKED" -eq 1 ]; then
  echo "SPEC_GUARDRAIL: Blocked write to $(basename "$FILE_PATH")"
  echo ""
  printf "Missing required sections:%b\n" "$MESSAGES"
  echo ""
  echo "To unblock:"
  echo "  1. Invoke code-fact-extractor on all identifiers in the spec"
  echo "  2. Populate ## Sources — each entry: \`path:LINE-LINE\` (branch: BRANCH, commit: SHA) — what it confirms"
  echo "  3. Fill ## Model Router — count Files to Change, apply decision tree, write 'Sonnet' or 'Opus'"
  echo ""
  echo "The spec must not be presented for engineer approval until both sections are complete."
  exit 2
fi

exit 0