---
name: drprod
description: "Spec Production Harness — fetches or creates a GitHub Issue, asks three grounding questions, then runs /spec with Sources + Model Router enforcement injected. Run /drprod <ISSUE_NUMBER|TASK> to start."
argument-hint: <ISSUE_NUMBER|TASK>
---

# /drprod — Spec Production Harness

Bootstraps a guarded spec-production session for a single GitHub Issue. Fetches or creates
the issue via `gh`, asks three grounding questions to anchor intent, then delegates to `/spec`
with Sources + Model Router enforcement injected. The `spec-guardrail` hook enforces the
output — no spec ships without verified `## Sources` and a filled `## Model Router`.

**What this solves:** Without a harness, the spec-writer receives a pre-digested brief and
skips verification — writing facts from assumptions rather than confirmed code. Grounding
questions anchor the brief to what the engineer actually intends to build.

---

## Usage

```
/drprod 12          — fetch GitHub Issue #12, run spec harness
/drprod DEMO-PRD    — search for an issue titled DEMO-PRD, or offer to create it
/drprod stop        — clean up tracker state for current active task
```

---

## Step 1 — Parse argument

Read `$ARGUMENTS`. Trim whitespace.

If empty, print usage and stop:
> "Usage: /drprod <ISSUE_NUMBER|TASK> — fetches or creates a GitHub Issue and starts a guarded spec session."

If `$ARGUMENTS` is `stop` → jump to **Stop Flow** at the bottom.

Otherwise treat as `<TASK>` and proceed.

---

## Step 2 — Resolve paths

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TASK="$ARGUMENTS"
TASK_DIR="${PROJECT}/.claude/task-progress"
TRACKER="${TASK_DIR}/${TASK}.md"

mkdir -p "$TASK_DIR"

echo "PROJECT: $PROJECT"
echo "TASK: $TASK"
echo "TRACKER: $TRACKER"
```

---

## Step 3 — Fetch or create GitHub Issue

### Fetch attempt

If `$TASK` is a number, run:
```bash
gh issue view "$TASK" --json number,title,body,state,labels,assignees
```

If `$TASK` is a string (not a number), search for a matching issue:
```bash
gh issue list --search "$TASK" --json number,title,body,state --limit 5
```

**If an issue is found**, display a summary:

```
──────────────────────────────────────────────────────────────
ISSUE:    #N
Title:    [title]
State:    [open/closed]
Labels:   [labels or none]
Assignee: [assignee or unassigned]

Body (first 400 chars):
[body truncated]
──────────────────────────────────────────────────────────────
```

Ask: **"Is this the right issue? (yes / no)"**

- **Yes** → set `ISSUE_NUMBER=N`, `ISSUE_TITLE=[title]`, continue to Step 4.
- **No** → "Stopping. Re-run `/drprod` with the correct issue number or title." and exit.

**If no issue found**, offer to create one:

> "No GitHub Issue found for '**TASK**'. Want me to create one? (yes / no)"

- **No** → "Stopping. Create the issue manually and re-run `/drprod <ISSUE_NUMBER>`." and exit.
- **Yes** → proceed to the guided creation flow below.

### Guided creation flow

Ask these questions one at a time — wait for each answer:

1. **Title:** "One-line issue title?"
2. **Body:** "Describe the work in 2–4 sentences. What problem does it solve and for whom?"
3. **Acceptance criteria:** "List acceptance criteria, one per line. (You can refine them in the spec.)"
4. **Labels:** "Any labels? (e.g. `enhancement`, `demo`, `feature` — or press Enter to skip)"

Once all answers are in, create the issue:

```bash
gh issue create \
  --title "<Q1 answer>" \
  --body "<Q2 answer>\n\n## Acceptance Criteria\n<Q3 answer>" \
  --label "<Q4 answer if provided>"
```

On success, print:
```
ISSUE_CREATED: #N — "[title]"
URL: https://github.com/<owner>/<repo>/issues/N
```

Set `ISSUE_NUMBER=N` and continue to Step 4.

---

## Step 4 — Check for existing spec

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SPEC_DIR="${PROJECT}/docs/GH-${ISSUE_NUMBER}"
SPEC="${SPEC_DIR}/SPEC.md"

if [ -f "$SPEC" ]; then
  echo "SPEC_EXISTS: $SPEC"
fi
```

If a spec already exists, display it and ask:
> "A spec already exists for Issue #ISSUE_NUMBER. Use it or regenerate? (use / regen)"

- **use** → skip to Step 7 (handoff), prompt `/implement GH-ISSUE_NUMBER`
- **regen** → continue to Step 5

---

## Step 5 — Three grounding questions

Ask one at a time. Wait for each answer before asking the next.

1. **Intent check:** "In one sentence — what is this issue actually building? (Issue titles drift from real intent — this anchors the spec.)"

2. **Hidden constraints:** "Any constraints the issue doesn't mention? (Performance requirements, backwards-compat, demo time limits, related in-progress work.)"

3. **Blast radius:** "Are there other files or features likely to be affected beyond what the issue calls out? List them or say none."

---

## Step 6 — Invoke code-fact-extractor on all identifiers

Before delegating to spec-writer, extract all technical identifiers from the issue body and
grounding answers — function names, hook names, type names, file paths, API routes, component
names, CSS tokens — and invoke the **code-fact-extractor** agent with the full list.

This step is mandatory. Do not send a spec-writer brief until extractor results are in hand.

Print: `"Extracted N identifiers. Running code-fact-extractor..."`

---

## Step 7 — Delegate to /spec

Set the task key:
```bash
SPEC_KEY="GH-${ISSUE_NUMBER}"
mkdir -p "${PROJECT}/docs/${SPEC_KEY}"
```

Invoke `/spec GH-ISSUE_NUMBER` now, with these items injected into the agent context:

**Issue content:** paste the full issue title + body verbatim.

**Engineer Notes (from Step 5):**
```
Intent: [engineer's answer to Q1]
Hidden constraints: [engineer's answer to Q2]
Blast radius: [engineer's answer to Q3]
```

**Extractor results (from Step 6):** append the full verification manifest.

**Required spec output — inject verbatim into the spec-writer delegation:**

> **REQUIRED — every spec must include these two final sections:**
>
> ### ## Model Router
> Count the Files to Change table. Apply the decision tree:
> - ≥ 3 files OR ≥ 2 top-level modules → **Opus / Enterprise Architect**
> - Architecture or design decision? → **Opus**
> - Shared contract change (API, DTO, hook signature)? → **Opus**
> - Otherwise → **Sonnet / General Engineer**
>
> Write the decision as a filled line: `**Decision:** Sonnet / General Engineer`
> A bracket placeholder `[ ]` will be blocked by the spec-guardrail hook.
>
> ### ## Sources
> List every file read to support a factual claim. Format per entry:
> `` `repo-relative/path/to/file.ext:LINE_START-LINE_END` (branch: BRANCH, commit: SHORT_SHA) — what this confirms ``
> Line numbers required. Branch required. Commit SHA (`git rev-parse --short HEAD`) required.
> Vague entries ("see file") are invalid. The spec-guardrail hook blocks the Write if Sources
> is absent or has no `path:line ... commit:` entries.

Spec saves to `docs/GH-ISSUE_NUMBER/SPEC.md`.

---

## Step 8 — Write process tracker and update issue

After the spec is approved:

```bash
TODAY=$(date +%Y-%m-%d)
INIT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$TRACKER" << EOF
# GH-${ISSUE_NUMBER} — /drprod Progress

**Started:** ${TODAY}
**Issue:** #${ISSUE_NUMBER} — ${ISSUE_TITLE}
**Spec:** docs/GH-${ISSUE_NUMBER}/SPEC.md
**Status:** Spec approved

## Steps
- [x] GitHub Issue confirmed
- [x] Grounding questions answered
- [x] code-fact-extractor run
- [x] Spec approved
- [ ] /dreng verification
- [ ] /implement complete
- [ ] PR opened

## Init time: ${INIT_TIME}
EOF
echo "Tracker written: $TRACKER"
```

Add a comment to the GitHub issue linking the spec:

```bash
gh issue comment "$ISSUE_NUMBER" \
  --body "Spec generated: \`docs/GH-${ISSUE_NUMBER}/SPEC.md\`
  
Run \`/dreng GH-${ISSUE_NUMBER}\` for adversarial claim verification, then \`/implement GH-${ISSUE_NUMBER}\` to build."
```

---

## Step 9 — Handoff

Print:

> "Spec approved and saved to `docs/GH-ISSUE_NUMBER/SPEC.md`. GitHub Issue #ISSUE_NUMBER updated.
>
> **Next:** Run `/dreng GH-ISSUE_NUMBER` for adversarial claim verification before implementation,
> or run `/implement GH-ISSUE_NUMBER` to go straight to building."

---

## Stop Flow

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TASK_DIR="${PROJECT}/.claude/task-progress"
TRACKER=$(ls "${TASK_DIR}/"*.md 2>/dev/null | head -1)

echo "Harness stopped."
if [ -n "$TRACKER" ]; then
  echo "Tracker: $TRACKER"
fi
echo "Run /drprod <ISSUE_NUMBER> to start a new session."
```
