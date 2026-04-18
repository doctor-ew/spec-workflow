#!/bin/bash
# reset-fail-counter.sh — Clears the failure counter on successful tool use
#
# Fires on PostToolUse for Bash|Edit|Write (the tools that can fail in a fix loop).
# Resets the consecutive-failure counter so escalation alerts only fire for
# truly consecutive failures, not ones separated by successful steps.
#
# Exit 0 always — this hook is silent.

HOOK_INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$(echo "${PWD}-$(git branch --show-current 2>/dev/null)" | tr -d '/ \n' | head -c 24)"
fi
COUNTER_FILE="/tmp/claude-fail-count-${SESSION_ID}"

rm -f "$COUNTER_FILE"
exit 0