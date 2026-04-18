#!/bin/bash
# fail-counter.sh — Failure escalation trigger
#
# Fires on PostToolUseFailure. Tracks consecutive tool failures within a session.
# After 2 failures, suggests escalating to the Enterprise Architect (Opus).
#
# State file: /tmp/claude-fail-count-<session_id>
# Resets automatically when a tool succeeds (see reset-fail-counter.sh).
#
# Exit 0 with stdout = advisory suggestion (engineer decides)
# Exit 0 with no output = proceed silently

HOOK_INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$(echo "${PWD}-$(git branch --show-current 2>/dev/null)" | tr -d '/ \n' | head -c 24)"
fi
COUNTER_FILE="/tmp/claude-fail-count-${SESSION_ID}"

# Increment counter
COUNT=1
if [ -f "$COUNTER_FILE" ]; then
  PREV=$(cat "$COUNTER_FILE" 2>/dev/null)
  [[ "$PREV" =~ ^[0-9]+$ ]] && COUNT=$((PREV + 1))
fi
echo "$COUNT" > "$COUNTER_FILE"

if [ "$COUNT" -ge 2 ]; then
  echo "ESCALATION ALERT: $COUNT consecutive tool failures in this session."
  echo "The General Engineer has hit repeated errors. Consider switching to the Enterprise Architect agent."
  echo "Say: 'Use the Enterprise Architect agent for this task' or 'escalate to architect'."
fi

exit 0