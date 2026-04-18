---
name: dreng
description: "Adversarial Engineering Lane — loads an approved spec, verifies every technical claim against source code via code-fact-extractor, surfaces conflicts for engineer review, then hard-gates into /implement. Run /dreng <TASK> to start."
argument-hint: <TASK>
---

# /dreng — Adversarial Engineering Lane

Consumes an approved spec and adversarially verifies every technical claim before a single
line of code is written. The engineer decides each conflict — CONFIRM as written, or OVERRIDE
with explicit reasoning. BLOCKED if unresolved claims remain. APPROVED gates into `/implement`.

**Credible Hulk principle:** AI does all the verification legwork. The engineer carries the
receipts and makes every override call. No claim reaches the codebase without a human sign-off.

**Note:** For spec production (the prior phase), use `/drprod <ISSUE_NUMBER>`.
If no spec exists yet, `/dreng` will invoke `/drprod` automatically before proceeding.

---

## Usage

```
/dreng GH-12         — adversarial claim review for GitHub Issue #12
/dreng DEMO-PRD      — adversarial claim review using docs/DEMO-PRD/SPEC.md
```

---

## Step 1 — Parse argument

Read `$ARGUMENTS`. Trim whitespace.

If empty, print usage and stop:
> "Usage: /dreng <TASK> — runs adversarial claim review for a task with an approved spec."

Otherwise treat as `<TASK>`.

---

## Step 2 — Resolve paths

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TASK="$ARGUMENTS"
TASK_DIR="${PROJECT}/.claude/task-progress"
SPEC="${PROJECT}/docs/${TASK}/SPEC.md"
CITATION="${TASK_DIR}/${TASK}-citations.jsonl"

mkdir -p "$TASK_DIR"

echo "PROJECT: $PROJECT"
echo "TASK: $TASK"
echo "SPEC: $SPEC"
echo "CITATION: $CITATION"
```

---

## Step 3 — Check spec exists (or invoke /drprod)

```bash
if [ ! -f "$SPEC" ]; then
  echo "SPEC_MISSING: No spec found at ${SPEC}"
fi
```

If no spec found, offer:
> "No spec found at `docs/TASK/SPEC.md`. Run `/drprod TASK` first to generate one?"

- **Yes** → invoke `/drprod TASK`. Wait for spec approval before continuing.
- **No** → stop.

After `/drprod` completes, re-check:
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
Re-run /drprod to regenerate the spec with Sources enforced.
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

**FOUND_MATCH — write silently:**
```json
{"claim": "<text>", "status": "VERIFIED", "source": {"file": "<path>", "line": N}, "challenge": null, "override_reasoning": null, "risk_level": null}
```

**NOT_FOUND + [NEW] — write silently:**
```json
{"claim": "<text>", "status": "NET_NEW", "source": null, "challenge": "Not in codebase — being created by this spec.", "override_reasoning": null, "risk_level": null}
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
{"claim": "<text>", "status": "VERIFIED", "source": {"file": "<path or null>", "line": null}, "challenge": "<extractor finding>", "override_reasoning": null, "risk_level": null}
```

**Choice B — OVERRIDE:**
Ask two follow-ups:
1. "Reasoning for override? (Required)"
2. "Risk level? HIGH / MEDIUM / LOW"

```json
{"claim": "<text>", "status": "VERIFIED_WITH_OVERRIDE", "source": {"file": "<path or null>", "line": null}, "challenge": "<extractor finding>", "override_reasoning": "<engineer text>", "risk_level": "<HIGH|MEDIUM|LOW>"}
```

**Choice C — BLOCK:**
```json
{"claim": "<text>", "status": "NOT_FOUND", "source": null, "challenge": "<extractor finding>", "override_reasoning": null, "risk_level": null}
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

To proceed: re-run /dreng TASK and for each blocked claim:
  - Choose B (OVERRIDE) with reasoning if the spec is still correct
  - Or update the spec to correct the claim, then re-run
```

Stop. Do not call /implement.

**If BLOCKED_COUNT = 0:**

```
DRENG GATE: APPROVED — all N claims verified or overridden with reasoning.
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

If no overrides: `"All N claims verified — no hot spots. Proceeding to /implement."`

---

## Step 10 — Call /implement

The hot-spot briefing is now in context. Invoke `/implement TASK` now.

`/implement` will read the spec at `docs/TASK/SPEC.md` and the citation file at
`.claude/task-progress/TASK-citations.jsonl` for full claim detail.