---
name: drew-eng
description: "Adversarial Engineering Lane — loads an approved spec, verifies every technical claim against source code via code-fact-extractor, gates into /implement, then runs a post-implement drift review and saves DRIFT.md to docs/{task}/. Run /drew-eng <TASK> to start."
argument-hint: <TASK>
---

# /drew-eng — Adversarial Engineering Lane

Consumes an approved spec and adversarially verifies every technical claim before a single
line of code is written. The engineer decides each conflict — CONFIRM as written, or OVERRIDE
with explicit reasoning. BLOCKED if unresolved claims remain. APPROVED gates into `/implement`.

After claim verification, gates into `/implement`. Once implementation is complete, runs
a drift review comparing ticket → spec → code and saves findings to `docs/TASK/DRIFT.md`.
Code review (DRY/SOLID/ACID/CoC/Big O) runs in `/drew-qa`.

**Credible Hulk principle:** AI does all the verification legwork. The engineer carries the
receipts and makes every override call. No claim reaches the codebase without a human sign-off.

**Note:** For spec production (the prior phase), use `/drew-product <ISSUE_NUMBER>`.
If no spec exists yet, `/drew-eng` will invoke `/drew-product` automatically before proceeding.

---

## Usage

```
/drew-eng GH-12         — adversarial claim review for GitHub Issue #12
/drew-eng DEMO-PRD      — adversarial claim review using docs/DEMO-PRD/SPEC.md
```

---

## Step 1 — Parse argument

Read `$ARGUMENTS`. Trim whitespace.

If empty, print usage and stop:
> "Usage: /drew-eng <TASK> — runs adversarial claim review for a task with an approved spec."

Otherwise treat as `<TASK>`.

---

## Step 2 — Resolve paths

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TASK="$ARGUMENTS"
TASK_DIR="${PROJECT}/.claude/task-progress"
SPEC="${PROJECT}/docs/${TASK}/SPEC.md"
CITATION="${TASK_DIR}/${TASK}-citations.jsonl"
REVIEW="${PROJECT}/docs/${TASK}/REVIEW.md"

mkdir -p "$TASK_DIR"
mkdir -p "${PROJECT}/docs/${TASK}"

echo "PROJECT: $PROJECT"
echo "TASK: $TASK"
echo "SPEC: $SPEC"
echo "CITATION: $CITATION"
echo "REVIEW: $REVIEW"
```

---

## Step 3 — Check spec exists (or invoke /drew-product)

```bash
if [ ! -f "$SPEC" ]; then
  echo "SPEC_MISSING: No spec found at ${SPEC}"
fi
```

If no spec found, offer:
> "No spec found at `docs/TASK/SPEC.md`. Run `/drew-product TASK` first to generate one?"

- **Yes** → invoke `/drew-product TASK`. Wait for spec approval before continuing.
- **No** → stop.

After `/drew-product` completes, re-check:
```bash
if [ ! -f "$SPEC" ]; then
  echo "DRENG_BLOCKED: Spec still missing — cannot proceed."
fi
```

---

## Step 4 — Check for existing citation file (resume logic)

```bash
if [ -f "$CITATION" ] && [ -s "$CITATION" ]; then
  EXISTING=$(wc -l < "$CITATION" | tr -d ' ')
  echo "CITATION_EXISTS: ${CITATION} (${EXISTING} entries)"
  echo "OFFER_RESUME: yes"
else
  echo "OFFER_RESUME: no"
fi
```

If `OFFER_RESUME: yes`, ask the engineer:

> "Found an existing citation file for **TASK** with **N** entries from a previous session.
>
> **A)** Resume — skip claims already cited, process remaining
> **B)** Start fresh — delete existing file and re-run all claims"

Wait for choice. If **B**:
```bash
rm "$CITATION"
echo "Citation file cleared."
```

---

## Step 5 — Extract claims from spec

Read the spec at `$SPEC` fully. Extract all technical claims across these categories:

| Category | Examples |
|----------|---------|
| **Function/method names + signatures** | `useMartaData`, `deriveStatus`, return type |
| **Type names, interfaces, enums** | `TransitVehicle`, `LineStatus` |
| **Field/property names** | `vehicles`, `isLoading`, `isError`, `route` |
| **File paths stated as authoritative** | `src/hooks/useMartaData.ts`, `src/app/HomeClient.tsx` |
| **Behavioral assertions stated as facts** | "returns undefined when error", "refreshInterval: 10000" |
| **Constants and magic values** | `"GOLD"`, `"BLUE"`, `w-80`, CSS token `bg-accent` |
| **CSS tokens / class names** | `bg-surface`, `text-error`, `border-border` |

Build a numbered claim list. Each claim is one verifiable assertion. Omit requirements
("should", "must", "will") — extract only factual assertions about the current codebase.

**Tag each claim `[EXISTING]` or `[NEW]`:**
- `[EXISTING]` — something that should currently exist in the codebase
- `[NEW]` — the spec is creating it (language: "create", "add", "implement", "new")

When in doubt, tag `[EXISTING]` — over-challenging is safer than accepting a fabricated claim.

Print before proceeding:
```
Extracted N claims from spec (X EXISTING, Y NEW). Beginning verification...
```

If resuming (Step 4 choice A), skip claims whose text already appears in the citation file.

---

## Step 5b — Verify ## Sources section

Read the `## Sources` section from `$SPEC`. If absent or empty, hard-stop:

```
DRENG_BLOCKED: Spec has no ## Sources section.
Every spec must end with a ## Sources section populated by code-fact-extractor results.
Re-run /drew-product to regenerate the spec with Sources enforced.
```

For each source entry, invoke **code-fact-extractor** with:
- The file path and line range
- The commit SHA from the entry (flag drift if HEAD differs)
- The description as the claim to confirm

| Result | Action |
|--------|--------|
| File exists, lines match, content matches description | Append `SOURCES_VERIFIED` silently |
| File exists but line range is off by > 5 lines | Surface as `SOURCES_CONFLICT` — line drift |
| HEAD commit differs from cited commit | Surface as `SOURCES_CONFLICT` — code changed since spec |
| File path not found | Surface as `SOURCES_CONFLICT` — path not found |
| Entry missing line number, branch, or commit SHA | Surface as `SOURCES_INVALID` |

For each conflict or invalid entry, present to engineer:

```
────────────────────────────────────────────────────────────────
SOURCES CHECK — `<path>:<lines>` (branch: <branch>, commit: <sha>)
Description: "<description>"

Extractor result: <what was actually found>

  A) CONFIRM — source is correct; extractor result is misleading
  B) NOTE DISCREPANCY — acknowledge drift; I'll update spec before PR
  C) BLOCK — this source is wrong; spec must be corrected now
────────────────────────────────────────────────────────────────
```

Choice **C** adds to the blocked list (evaluated in Step 8).

Print summary:
```
Sources verified: N/total confirmed. Conflicts: X. Blocked: Y.
```

---

## Step 6 — Per-claim extractor loop

For each claim in the list, invoke **code-fact-extractor** with the claim text and any
specific files mentioned. Pass project root as search context.

Map results:

| Outcome | Condition | Action |
|---------|-----------|--------|
| `FOUND_MATCH` | Extractor confirms claim exactly | Write `VERIFIED` citation silently, continue |
| `FOUND_CONFLICT` | Identifier found but details differ | Surface to challenge loop (Step 7) |
| `NOT_FOUND` + `[EXISTING]` | Should exist, doesn't | Surface to challenge loop (Step 7) |
| `NOT_FOUND` + `[NEW]` | Spec is creating it | Write `NET_NEW` citation silently, continue |

**Before writing any citation entry:** copy the `Extracted at:` timestamp from the extractor
report header. Use it as `extractor_run` in every entry written from this extractor call.
If the report is missing this field, run `date -u +%Y-%m-%dT%H:%M:%SZ` and use that.

**FOUND_MATCH — write silently:**
```json
{"claim": "<text>", "status": "VERIFIED", "source": {"file": "<path>", "line": N}, "challenge": null, "override_reasoning": null, "risk_level": null, "extractor_run": "<ISO-8601 UTC timestamp>"}
```

**NOT_FOUND + [NEW] — write silently:**
```json
{"claim": "<text>", "status": "NET_NEW", "source": null, "challenge": "Not in codebase — being created by this spec.", "override_reasoning": null, "risk_level": null, "extractor_run": "<ISO-8601 UTC timestamp>"}
```

---

## Step 7 — Interactive challenge loop

For each FOUND_CONFLICT or NOT_FOUND [EXISTING] claim:

```
────────────────────────────────────────────────────────────────
CLAIM [N/total]: "<claim text>"

Extractor result: <what the extractor actually found>

  A) CONFIRM as VERIFIED — extractor is misleading; claim is correct as written
  B) OVERRIDE — I acknowledge the discrepancy; I'll provide reasoning
  C) BLOCK — I need to investigate this before proceeding
────────────────────────────────────────────────────────────────
```

**Choice A — CONFIRM:**
```json
{"claim": "<text>", "status": "VERIFIED", "source": {"file": "<path or null>", "line": null}, "challenge": "<extractor finding>", "override_reasoning": null, "risk_level": null, "extractor_run": "<ISO timestamp>"}
```

**Choice B — OVERRIDE:**
Ask two follow-ups:
1. "Reasoning for override? (Required)"
2. "Risk level? HIGH / MEDIUM / LOW"

```json
{"claim": "<text>", "status": "VERIFIED_WITH_OVERRIDE", "source": {"file": "<path or null>", "line": null}, "challenge": "<extractor finding>", "override_reasoning": "<engineer text>", "risk_level": "<HIGH|MEDIUM|LOW>", "extractor_run": "<ISO timestamp>"}
```

**Choice C — BLOCK:**
```json
{"claim": "<text>", "status": "NOT_FOUND", "source": null, "challenge": "<extractor finding>", "override_reasoning": null, "risk_level": null, "extractor_run": "<ISO timestamp>"}
```

Add to the blocked list.

---

## Step 8 — Gate evaluation

Count `NOT_FOUND` entries with no override reasoning:

```bash
python3 - "$CITATION" << 'PYEOF'
import json, sys
path = sys.argv[1]
blocked = []
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            e = json.loads(line)
            if e.get("status") == "NOT_FOUND":
                blocked.append(e.get("claim", "(unknown)"))
except FileNotFoundError:
    print("GATE_ERROR: citation file not found")
    sys.exit(1)
print(f"BLOCKED_COUNT: {len(blocked)}")
for c in blocked:
    print(f"  BLOCKED: {c}")
PYEOF
```

**If BLOCKED_COUNT > 0:**

```
DRENG GATE: BLOCKED

Unresolved claims (status=NOT_FOUND, no override reasoning):
  [list each]

To proceed: re-run /drew-eng TASK and for each blocked claim:
  - Choose B (OVERRIDE) with reasoning if the spec is still correct
  - Or update the spec to correct the claim, then re-run
```

Stop. Do not call /implement.

**If BLOCKED_COUNT = 0:**

```
DRENG GATE: APPROVED — all N claims verified or overridden with reasoning.
```

Update the ACTIVE file phase to implement:

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ACTIVE="${PROJECT}/.claude/task-progress/ACTIVE"
if [ -f "$ACTIVE" ]; then
  EXISTING_INIT=$(grep CXENG_INIT_TIME "$ACTIVE" | cut -d= -f2 || true)
  INIT_TIME="${EXISTING_INIT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  TICKET=$(grep CXENG_TICKET "$ACTIVE" | cut -d= -f2 || echo "$TASK")
  cat > "$ACTIVE" << EOF
CXENG_TICKET=${TICKET}
CXENG_PHASE=implement
CXENG_INIT_TIME=${INIT_TIME}
EOF
  echo "Phase set: implement"
fi
```

Continue to Step 9.

---

## Step 9 — Emit hot-spot briefing

Read `$CITATION`. Find all `VERIFIED_WITH_OVERRIDE` entries. Group by `risk_level` (HIGH → MEDIUM → LOW).

```
══════════════════════════════════════════════════════════════════
TASK Implementation Hot Spots

These spec claims were challenged during adversarial review.
Pay attention to these areas during implementation.
══════════════════════════════════════════════════════════════════

### HIGH RISK
- "<claim>" (<file>:<line or ?>)
  Extractor found: <challenge>
  Override: "<override_reasoning>"

### MEDIUM RISK
[same format, or "(none)"]

### LOW RISK
[same format, or "(none)"]

Full citation file: .claude/task-progress/TASK-citations.jsonl
══════════════════════════════════════════════════════════════════
```

If no overrides: `"All N claims verified — no hot spots. Proceeding to code review."`

---

## Step 10 — Call /implement

The hot-spot briefing is now in context. Invoke `/implement TASK` now.

`/implement` will read the spec at `docs/TASK/SPEC.md` and the citation file at
`.claude/task-progress/TASK-citations.jsonl` for full claim detail.

Wait for `/implement` to complete before proceeding to Step 11.

---

## Step 11 — Post-implement drift review

After implementation completes, compare ticket → spec → code to surface any divergence.

### 11a — Collect sources

```bash
BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || echo "main")

if echo "$TASK" | grep -qE '^GH-[0-9]+$'; then
  ISSUE_NUM=$(echo "$TASK" | sed 's/GH-//')
  gh issue view "$ISSUE_NUM" --json body,title
  TICKET_IS_SPEC=false
else
  TICKET_IS_SPEC=true
fi
```

If `TICKET_IS_SPEC=true`, the spec is the ticket — skip ticket ↔ spec check and note it in DRIFT.md.

Read spec acceptance criteria from `$SPEC`. Get the implementation diff:
```bash
git diff "$BASE"...HEAD -- .
```

### 11b — Ticket ↔ Spec alignment (skip if TICKET_IS_SPEC=true)

For each ticket AC → find it in spec: **COVERED** or **SPEC_GAP**.
For each spec AC not traceable to a ticket AC: **SCOPE_DRIFT**.

### 11c — Spec ↔ Code alignment

For each spec AC, scan the diff for implementation evidence (**file:line required**):

| Result | Meaning |
|--------|---------|
| `IMPLEMENTED` | Clear evidence in changed or new code |
| `PARTIAL` | Present but incomplete |
| `IMPL_GAP` | No evidence found |

Print:
```
Drift scan complete:
  SPEC_GAP:    N  (ticket ACs not in spec)
  SCOPE_DRIFT: N  (spec ACs not in ticket)
  IMPL_GAP:    N  (spec ACs not in code)
  ALIGNED:     N
```

If SPEC_GAP > 0 or IMPL_GAP > 0:
```
⚠ DRIFT DETECTED — review before opening PR:
  SPEC_GAP:  [list]
  IMPL_GAP:  [list]
```

---

## Step 12 — Save DRIFT.md

```bash
DRIFT="${PROJECT}/docs/${TASK}/DRIFT.md"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
TODAY=$(date +%Y-%m-%d)
```

Write to `$DRIFT`:

```markdown
## Drift Review

**Task:** TASK
**Date:** YYYY-MM-DD
**Branch:** BRANCH
**Compared:** Ticket ↔ Spec ↔ Implementation

---

### Ticket ↔ Spec Alignment

[If TICKET_IS_SPEC: "Spec used directly as ticket — alignment check skipped."]

| Ticket Criterion | In Spec | Status |
|-----------------|---------|--------|
[rows or "(none detected)"]

### Scope Drift (spec adds beyond ticket)

| Spec Requirement | Status |
|-----------------|--------|
[rows or "(none)"]

### Spec ↔ Code Alignment

| Spec Criterion | Evidence | Status |
|---------------|---------|--------|
[rows]

---

### Summary
- SPEC_GAP:    N
- SCOPE_DRIFT: N
- IMPL_GAP:    N
- ALIGNED:     N

### Verdict
[ALIGNED / DRIFT_DETECTED — list SPEC_GAP + IMPL_GAP items by name]
```

Print: `DRIFT saved: docs/TASK/DRIFT.md`

---

## Step 13 — Handoff to /drew-qa

```
══════════════════════════════════════════════════════════════════
TASK Implementation Complete

  Spec:         docs/TASK/SPEC.md
  Drift report: docs/TASK/DRIFT.md
  Citations:    .claude/task-progress/TASK-citations.jsonl

Next: /drew-qa TASK
  → Runs code review (DRY/SOLID/ACID/CoC/BigO), validates all ACs, runs tests.
  → Saves REVIEW.md + QA.md. Gates into /drew-deploy.
══════════════════════════════════════════════════════════════════
```
