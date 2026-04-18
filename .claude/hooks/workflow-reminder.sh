#!/bin/bash
# workflow-reminder.sh
#
# Injected into Claude's context at session start and after compaction.
# stdout from this script becomes part of Claude's context window.
# Keep it short — context is precious.

cat <<'EOF'
## DoctorEws Laboratory — Spec-Driven Workflow

The spec-driven development framework is active for this repo.

**Before writing any code:**
1. Ask what the engineer is working on
2. If there's a ticket or task, offer to run /spec to generate a spec
3. Read CLAUDE.md for repo-specific conventions and commands
4. No code ships without an approved spec

**Available commands:** /spec · /review-spec · /implement · /review · /preflight · /investigate
**Agents:** Spec Writer · Enterprise Architect · General Engineer · QA · Code Reviewer (see .claude/agents/)
**Key rule:** Spec → Implement → QA validates → Preflight. In that order, always.
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
