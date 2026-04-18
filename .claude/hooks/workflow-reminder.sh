#!/bin/bash
# workflow-reminder.sh
#
# Injected into Claude's context at session start and after compaction.
# stdout from this script becomes part of Claude's context window.
# Keep it short — context is precious.

cat <<'EOF'
## Spec-Driven Workflow

The spec-driven development framework is active for this repo.

**Before writing any code:**
1. Ask what the engineer is working on
2. If there's a GitHub Issue or task, run /drprod to start a guarded spec session
3. Read CLAUDE.md for repo-specific conventions and commands
4. No code ships without an approved spec

**Available commands:** /drprod · /dreng · /spec · /implement · /review · /review-spec · /preflight · /investigate
**Harness flow:** /drprod <ISSUE> → approve → /dreng <ISSUE> → /implement <ISSUE>
**Agents:** Spec Writer · Enterprise Architect · General Engineer · QA · Code Reviewer (see .claude/agents/)

**SPEC GUARDRAIL is active.**
Any Write to a SPEC*.md file will be blocked if:
- ## Sources is missing or has no path:line + commit: entries
- ## Model Router is missing or Decision field is not filled in
EOF

# Inject recent lessons if they exist
if [ -f ".claude/lessons.md" ]; then
  LESSON_COUNT=$(grep -c "^## " .claude/lessons.md 2>/dev/null || echo 0)
  if [ "$LESSON_COUNT" -gt 0 ]; then
    echo ""
    echo "## Lessons from prior sessions (last 3)"
    grep -A 2 "^## " .claude/lessons.md | grep -v "^--$" | tail -9
  fi
fi
