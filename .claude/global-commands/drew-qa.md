---
name: drew-qa
description: "QA Gate Orchestration — runs /review-spec then /review in sequence, updates ACTIVE phase to qa, and emits a combined gate result. Gates into /drew-deploy. Run /drew-qa <TASK> after /drew-eng."
argument-hint: <TASK>
---

# /drew-qa — QA Gate Orchestration

Runs after `/drew-eng` (implementation complete, DRIFT.md in hand). Orchestrates the full
post-implementation QA gate: spec validation (`/review-spec`) followed by unified code
review (`/review`). Produces `QA.md` and `REVIEW.md`. A gate OPEN result enables
`/drew-deploy`.

---

## Usage

```
/drew-qa GH-12         — QA gate for GitHub Issue #12
/drew-qa DEMO-PRD      — QA gate using docs/DEMO-PRD/SPEC.md
```

---

## Step 1 — Parse argument

Read `$ARGUMENTS`. Trim whitespace.

If empty, check ACTIVE file:
```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ACTIVE="${PROJECT}/.claude/task-progress/ACTIVE"
if [ -f "$ACTIVE" ]; then
  . "$ACTIVE"
  echo "TASK from ACTIVE: $CXENG_TICKET"
fi
```

If still no task: "Usage: /drew-qa <TASK> — run after /drew-eng TASK completes."

---

## Step 2 — Resolve paths and update ACTIVE phase

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TASK="${ARGUMENTS:-$CXENG_TICKET}"
SPEC="${PROJECT}/docs/${TASK}/SPEC.md"
DRIFT="${PROJECT}/docs/${TASK}/DRIFT.md"
ACTIVE="${PROJECT}/.claude/task-progress/ACTIVE"

echo "PROJECT: $PROJECT"
echo "TASK:    $TASK"
echo "SPEC:    $SPEC"
```

Update ACTIVE file phase to qa:

```bash
if [ -f "$ACTIVE" ]; then
  EXISTING_INIT=$(grep CXENG_INIT_TIME "$ACTIVE" | cut -d= -f2 || true)
  INIT_TIME="${EXISTING_INIT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  cat > "$ACTIVE" << EOF
CXENG_TICKET=${TASK}
CXENG_PHASE=qa
CXENG_INIT_TIME=${INIT_TIME}
EOF
  echo "Phase set: qa"
fi
```

---

## Step 3 — Prerequisites check

```bash
[ -f "$SPEC" ] || echo "MISSING: $SPEC"
```

If SPEC missing:
> "No spec found at `docs/TASK/SPEC.md`. Run `/drew-product TASK` and `/drew-eng TASK` first."
Stop.

If DRIFT.md missing, warn but continue:
> "⚠ DRIFT.md not found — /drew-eng post-implement drift review may not have run. Continuing without drift context."

Announce:
> "QA gate starting for TASK — /review-spec → /review"

---

## Step 4 — Run /review-spec

Execute all steps from `commands/review-spec.md` for this task.

This will:
- Load spec (`docs/TASK/SPEC.md`), all files changed on this branch, and the task description
- Validate spec ↔ task coverage and code ↔ spec alignment per acceptance criterion
- Check for scope violations (changes outside the spec)
- Write `docs/TASK/QA.md`
- Return a verdict: **PASS** / **FAIL** / **PASS WITH NOTES**

**If verdict is FAIL — stop:**

```
QA gate blocked at /review-spec — TASK

Spec alignment failed. Review docs/TASK/QA.md for findings.
Fix the listed issues and re-run /drew-qa TASK.
```

Do not proceed to Step 5.

**If verdict is PASS or PASS WITH NOTES:** continue.

---

## Step 5 — Run /review

Execute all steps from `commands/review.md` for this task.

This will:
- Load spec, QA report (`docs/TASK/QA.md`), and changed files
- Detect security signals in changed paths and run security-auditor in parallel if triggered
- Run DRY / SOLID / ACID / CoC code quality review
- Save `docs/TASK/REVIEW.md`
- If verdict is APPROVE with no BLOCKs → ask the engineer if ready to ship

---

## Step 6 — Combined gate result

After `/review` completes, emit the combined summary:

```
══════════════════════════════════════════════════════════════════
QA Gate — TASK

/review-spec:  PASS | PASS WITH NOTES | FAIL
/review:       APPROVE | REQUEST CHANGES | REJECT

Gate: OPEN | BLOCKED
══════════════════════════════════════════════════════════════════
```

**Gate OPEN:** review-spec is PASS or PASS WITH NOTES, and /review has no BLOCKs.
**Gate BLOCKED:** review-spec returned FAIL, or /review contains one or more BLOCKs.

When BLOCKED: list every blocking item clearly. Instruct the engineer to fix each one and
re-run `/drew-qa TASK`.

When OPEN:

```
Gate OPEN — ready for deployment.

Next: /drew-deploy TASK [dev|staging|prod]
```

Update tracker if it exists:

```bash
TRACKER="${PROJECT}/.claude/task-progress/${TASK}.md"
if [ -f "$TRACKER" ]; then
  sed -i '' 's/- \[ \] \/drew-qa gate: PASS/- [x] \/drew-qa gate: PASS/' "$TRACKER" 2>/dev/null
fi
```
