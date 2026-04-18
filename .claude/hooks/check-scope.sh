#!/bin/bash
# check-scope.sh — Model Router scope detection
#
# Fires on PreToolUse Edit|Write. Checks whether the session has grown beyond
# General Engineer (Sonnet) scope and suggests escalating to Enterprise Architect (Opus).
#
# Exit 0 with stdout message = advisory suggestion (engineer decides)
# Exit 0 with no output     = proceed silently
# Exit 2                     = block (not used here — router is advisory only)

CHANGED_FILES=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
TOTAL_FILES=$((CHANGED_FILES + STAGED_FILES))

# Count unique top-level directories changed (proxy for modules spanned) — include staged files
MODULES=$({ git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } | cut -d'/' -f1 | sort -u | wc -l | tr -d ' ')

if [ "$TOTAL_FILES" -ge 3 ]; then
  echo "SCOPE ALERT: $TOTAL_FILES files changed. Consider switching to Opus / Enterprise Architect."
  echo "Override: if these are intentional small changes across files, continue with Sonnet."
fi

if [ "$MODULES" -ge 2 ]; then
  echo "SCOPE ALERT: Changes span $MODULES top-level directories. Consider switching to Opus / Enterprise Architect."
  echo "Override: if these are independent small changes, continue with Sonnet."
fi

exit 0