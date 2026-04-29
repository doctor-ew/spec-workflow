#!/bin/bash
# drew-post-tool-use.sh — /drew-product Quality Gate (PostToolUse hook)
#
# Installed into project settings.json by /drew-product <TASK>. Removed by /drew-product stop.
# Fires after every tool call. Filters to Agent calls in spec phase only.
#
# Purpose: after spec-writer Agent completes, verify that citation file exists
# and has at least one VERIFIED entry. Injects failure message into Claude context if not.
#
# Exit 0 always — PostToolUse cannot hard-block.
# Failure is communicated via stdout → injected into Claude's context.

# ── Harness state ──────────────────────────────────────────────────────────────
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ACTIVE="${PROJECT}/.claude/task-progress/ACTIVE"

# No harness active — pass through silently
[ -f "$ACTIVE" ] || exit 0

# shellcheck source=/dev/null
. "$ACTIVE"

# Only intercept during spec phase
[ "${CXENG_PHASE:-}" = "spec" ] || exit 0

# ── Read stdin ─────────────────────────────────────────────────────────────────
if ! [ -t 0 ]; then
  INPUT=$(cat)
else
  exit 0
fi

# ── Parse tool_name ────────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
  echo "DREW_WARN: python3 not found — quality gate disabled."
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', ''))
except Exception:
    print('')
" 2>/dev/null)

[ "$TOOL_NAME" = "Agent" ] || exit 0

# ── Citation verification ──────────────────────────────────────────────────────
CITATION_FILE="${PROJECT}/.claude/task-progress/${CXENG_TICKET}-citations.jsonl"

if [ ! -f "$CITATION_FILE" ] || [ ! -s "$CITATION_FILE" ]; then
  echo "┌─────────────────────────────────────────────────────────────────────┐"
  echo "│  DREW QUALITY GATE FAILED                                           │"
  echo "├─────────────────────────────────────────────────────────────────────┤"
  echo "│  Task:          ${CXENG_TICKET}"
  echo "│  Citation file: ${CITATION_FILE}"
  echo "│  Status:        ABSENT or EMPTY"
  echo "├─────────────────────────────────────────────────────────────────────┤"
  echo "│  REQUIRED ACTIONS:                                                  │"
  echo "│  1. Invoke code-fact-extractor for every identifier and claim       │"
  echo "│     in the spec before approving it.                                │"
  echo "│  2. Write VERIFIED results to:                                      │"
  echo "│     .claude/task-progress/${CXENG_TICKET}-citations.jsonl           │"
  echo "│  3. Re-run spec-writer Agent after citations are verified.          │"
  echo "└─────────────────────────────────────────────────────────────────────┘"
  exit 0
fi

# Check for at least one VERIFIED entry
VERIFIED_COUNT=$(python3 -c "
import json, sys
count = 0
try:
    with open('${CITATION_FILE}') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                e = json.loads(line)
                if e.get('status') in ('VERIFIED', 'VERIFIED_WITH_OVERRIDE', 'NET_NEW'):
                    count += 1
            except Exception:
                pass
except Exception:
    pass
print(count)
" 2>/dev/null)

if [ "${VERIFIED_COUNT:-0}" -eq 0 ]; then
  echo "┌─────────────────────────────────────────────────────────────────────┐"
  echo "│  DREW QUALITY GATE FAILED — no VERIFIED citations                  │"
  echo "├─────────────────────────────────────────────────────────────────────┤"
  echo "│  Citation file exists but has no VERIFIED entries.                  │"
  echo "│  Run code-fact-extractor and populate citations before approving.   │"
  echo "└─────────────────────────────────────────────────────────────────────┘"
  exit 0
fi

# ── Gate passed — update tracker ──────────────────────────────────────────────
TRACKER="${PROJECT}/.claude/task-progress/${CXENG_TICKET}.md"
if [ -f "$TRACKER" ]; then
  sed -i '' 's/- \[ \] Spec passed quality gate/- [x] Spec passed quality gate/' "$TRACKER" 2>/dev/null
fi

echo "DREW QUALITY GATE: PASS — ${VERIFIED_COUNT} verified citation(s) found."

exit 0
