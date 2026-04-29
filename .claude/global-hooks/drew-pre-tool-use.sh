#!/bin/bash
# drew-pre-tool-use.sh — /drew-product Briefing Gate (PreToolUse hook)
#
# Installed into project settings.json by /drew-product <TASK>. Removed by /drew-product stop.
# Fires before every tool call. Filters to Agent calls in spec phase only.
#
# Purpose: block pre-digested briefs from reaching spec-writer before
# code-fact-extractor has run. Prevents fabricated claims baked into
# orchestrator research from being passed as facts to the spec-writer.
#
# Exit 0 = allow
# Exit 2 = block — message shown to Claude, which must comply

# ── Harness state ──────────────────────────────────────────────────────────────
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ACTIVE="${PROJECT}/.claude/task-progress/ACTIVE"

# No harness active — pass through silently
[ -f "$ACTIVE" ] || exit 0

# Source harness state: CXENG_TICKET, CXENG_PHASE, CXENG_INIT_TIME
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

# ── Parse tool_name and prompt length ─────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
  echo "DREW_WARN: python3 not found — briefing gate disabled. Install python3 to enable."
  exit 0
fi

PARSE_OUT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    tool = d.get('tool_name', '')
    prompt = d.get('tool_input', {}).get('prompt', '')
    print(tool)
    print(len(prompt))
except Exception:
    print('')
    print('0')
" 2>/dev/null)

TOOL_NAME=$(echo "$PARSE_OUT" | sed -n '1p')
PROMPT_LEN=$(echo "$PARSE_OUT" | sed -n '2p')

# Only applies to Agent tool calls
[ "$TOOL_NAME" = "Agent" ] || exit 0

# ── Block oversized brief with no citation evidence ────────────────────────────
CITATION_FILE="${PROJECT}/.claude/task-progress/${CXENG_TICKET}-citations.jsonl"

if [ "${PROMPT_LEN:-0}" -gt 500 ] 2>/dev/null && [ ! -s "$CITATION_FILE" ]; then
  echo "DREW BRIEFING GATE: Brief is ${PROMPT_LEN} chars — pre-digested research detected."
  echo "Citation file is absent or empty: ${CXENG_TICKET}-citations.jsonl"
  echo ""
  echo "REQUIRED before delegating to spec-writer:"
  echo "  1. Invoke code-fact-extractor for every identifier, return code, and"
  echo "     technical claim in your research brief."
  echo "  2. Write results to: .claude/task-progress/${CXENG_TICKET}-citations.jsonl"
  echo ""
  echo "This prevents fabricated or inferred claims from being baked into the spec"
  echo "as facts without source verification. Do not delegate until citations exist."
  exit 2
fi

exit 0
