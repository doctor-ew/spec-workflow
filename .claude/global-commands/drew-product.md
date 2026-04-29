---
name: drew-product
description: "Spec Production Harness — fetches or creates a GitHub Issue, installs briefing gate hooks, asks three grounding questions, then delegates to /spec with Sources + Model Router enforcement injected. Run /drew-product <ISSUE_NUMBER|TASK> to init, /drew-product stop to restore settings."
argument-hint: <ISSUE_NUMBER|TASK|stop>
---

# /drew-product — Spec Production Harness

Bootstraps a guarded spec-production session for a single GitHub Issue. Installs briefing
gate hooks into project `settings.json` at runtime, creates a process tracker, asks three
grounding questions before delegating to the spec-writer, and injects verification rules
into session context. Restores original settings on stop.

**What this solves:** Without a harness, the spec-writer receives a pre-digested brief and
skips verification — writing facts from assumptions rather than confirmed code. Hook gates
enforce the verification protocol at agent call boundaries. The three grounding questions
anchor the brief to what the engineer actually intends to build.

**Note:** This is the spec production harness. For the adversarial engineering lane that
verifies spec claims before implementation, use `/drew-eng <TASK>`.

---

## Usage

```
/drew-product 12          — init spec harness for GitHub Issue #12
/drew-product DEMO-PRD    — search for an issue titled DEMO-PRD, or offer to create it
/drew-product stop        — restore settings.json and deactivate harness
```

---

## Step 1 — Parse argument

Read `$ARGUMENTS`. Trim whitespace.

- If `$ARGUMENTS` is `stop` → jump to **Stop Flow** at the bottom.
- If `$ARGUMENTS` is empty → print usage and stop:
  > "Usage: /drew-product <ISSUE_NUMBER|TASK> to init, /drew-product stop to exit the harness."
- Otherwise → treat as `<TASK>` and proceed to **Init Flow**.

---

## Init Flow

### Step 0 — Fetch or create GitHub Issue

Before installing hooks or mutating any settings, confirm the issue exists.

#### Fetch attempt

If `$TASK` is a number:
```bash
gh issue view "$TASK" --json number,title,body,state,labels,assignees
```

If `$TASK` is a string (not a number):
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

- **Yes** → set `ISSUE_NUMBER=N`, `ISSUE_TITLE=[title]`, continue to Step 1a.
- **No** → "Stopping. Re-run `/drew-product` with the correct issue number or title." and exit.

**If no issue found**, offer to create one:

> "No GitHub Issue found for '**TASK**'. Want me to create one? (yes / no)"

- **No** → "Stopping. Create the issue manually and re-run `/drew-product <ISSUE_NUMBER>`." and exit.
- **Yes** → guided creation flow below.

#### Guided creation flow

Ask one at a time — wait for each answer:

1. **Title:** "One-line issue title?"
2. **Body:** "Describe the work in 2–4 sentences. What problem does it solve and for whom?"
3. **Acceptance criteria:** "List acceptance criteria, one per line. (You can refine them in the spec.)"
4. **Labels:** "Any labels? (e.g. `enhancement`, `demo`, `feature` — or press Enter to skip)"

Then create:

```bash
gh issue create \
  --title "<Q1 answer>" \
  --body "<Q2 answer>\n\n## Acceptance Criteria\n<Q3 answer>" \
  --label "<Q4 answer if provided>"
```

On success:
```
ISSUE_CREATED: #N — "[title]"
URL: https://github.com/<owner>/<repo>/issues/N
```

Set `ISSUE_NUMBER=N`, `ISSUE_TITLE=[title]`, continue to Step 1a.

---

### Step 1a — Resolve paths

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TASK="GH-${ISSUE_NUMBER}"
TASK_DIR="${PROJECT}/.claude/task-progress"
ACTIVE="${TASK_DIR}/ACTIVE"
BACKUP="${TASK_DIR}/${TASK}-settings-backup.json"
TRACKER="${TASK_DIR}/${TASK}.md"
CITATION="${TASK_DIR}/${TASK}-citations.jsonl"
SETTINGS="${PROJECT}/.claude/settings.json"
SPEC="${PROJECT}/docs/${TASK}/SPEC.md"

mkdir -p "$TASK_DIR"
mkdir -p "${PROJECT}/docs/${TASK}"

echo "PROJECT: $PROJECT"
echo "TASK: $TASK"
echo "ACTIVE: $ACTIVE"
echo "BACKUP: $BACKUP"
echo "TRACKER: $TRACKER"
echo "SETTINGS: $SETTINGS"
```

---

### Step 1b — Crash check (stale backup detection)

```bash
if [ -f "$BACKUP" ] && [ -f "$TRACKER" ]; then
  if ! grep -q '\- \[x\] PR opened' "$TRACKER" 2>/dev/null; then
    echo "DREW_CRASH_DETECTED: prior harness session found for ${TASK}."
    echo "  Backup: $BACKUP"
    echo "  Tracker: $TRACKER"
    echo "  PR was NOT opened — harness may not have been stopped cleanly."
    echo "OFFER_RESTORE: yes"
  else
    echo "OFFER_RESTORE: no"
    echo "Prior session complete (PR opened). Starting fresh."
    rm -f "$BACKUP"
  fi
else
  echo "OFFER_RESTORE: no"
fi
```

If `OFFER_RESTORE: yes`, ask the engineer:

> "Prior harness session for **TASK** found without a clean stop. The settings backup may not
> have been restored.
>
> **A)** Restore settings from backup now and start fresh
> **B)** Skip restore and continue (assume settings are already clean)"

If **A**:
```bash
cp "$BACKUP" "$SETTINGS"
echo "Settings restored from backup."
```

Continue regardless of choice.

---

### Step 1c — Backup current settings.json

```bash
python3 - "$SETTINGS" "$BACKUP" << 'PYEOF'
import sys, json, shutil
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    cfg = json.load(f)  # validate it parses
shutil.copy2(src, dst)
print(f"Backed up: {src} -> {dst}")
PYEOF
```

If this fails (settings.json does not parse), **stop and report** — do not continue with a corrupt settings file.

---

### Step 1d — Write ACTIVE harness state file

```bash
INIT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$ACTIVE" << EOF
CXENG_TICKET=${TASK}
CXENG_PHASE=spec
CXENG_INIT_TIME=${INIT_TIME}
EOF
echo "ACTIVE file written: $ACTIVE"
cat "$ACTIVE"
```

---

### Step 1e — Install enforcement hooks into settings.json

Add two hook entries tagged `"_drew": true` (for easy removal on stop). The hooks
live globally and use the ACTIVE file to gate by task and phase.

```bash
python3 - "$SETTINGS" << 'PYEOF'
import sys, json

path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

hooks = cfg.setdefault("hooks", {})

# ── PreToolUse: Briefing Gate ──────────────────────────────────────────────────
pre_hooks = hooks.setdefault("PreToolUse", [])
pre_hooks = [e for e in pre_hooks if not e.get("_drew")]
pre_hooks.append({
    "matcher": "Agent",
    "_drew": True,
    "hooks": [{
        "type": "command",
        "command": "bash \"${HOME}/.claude/hooks/drew-pre-tool-use.sh\""
    }]
})
hooks["PreToolUse"] = pre_hooks

# ── PostToolUse: Quality Gate ──────────────────────────────────────────────────
post_hooks = hooks.setdefault("PostToolUse", [])
post_hooks = [e for e in post_hooks if not e.get("_drew")]
post_hooks.append({
    "matcher": "Agent",
    "_drew": True,
    "hooks": [{
        "type": "command",
        "command": "bash \"${HOME}/.claude/hooks/drew-post-tool-use.sh\""
    }]
})
hooks["PostToolUse"] = post_hooks

cfg["hooks"] = hooks

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print("Hooks installed: PreToolUse (briefing-gate) + PostToolUse (quality-gate)")
PYEOF
```

---

### Step 1f — Write process tracker

```bash
TODAY=$(date +%Y-%m-%d)
cat > "$TRACKER" << EOF
# ${TASK} — /drew-product Progress

**Started:** ${TODAY}
**Issue:** #${ISSUE_NUMBER} — ${ISSUE_TITLE}
**Spec:** docs/${TASK}/SPEC.md (pending)
**Citations:** .claude/task-progress/${TASK}-citations.jsonl (pending)
**Status:** Initialized

## Steps
- [ ] Spec passed quality gate (PostToolUse verified: citation file populated)
- [ ] /drew-eng approved
- [ ] /implement complete
- [ ] /drew-qa gate: PASS
- [ ] PR opened

## Harness State
- Hooks installed: PreToolUse (briefing-gate), PostToolUse (quality-gate)
- Original settings backed up at: .claude/task-progress/${TASK}-settings-backup.json
- Init time: ${INIT_TIME}
EOF
echo "Tracker: $TRACKER"
```

---

### Step 1g — Graphify staleness check

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
GRAPH="${PROJECT}/graphify-out/graph.json"

if [ ! -f "$GRAPH" ]; then
  echo "GRAPHIFY_NOT_AVAILABLE: no graph.json at ${GRAPH}"
  echo "Run /graphify to build a knowledge graph for better citation coverage."
else
  MTIME=$(stat -f %m "$GRAPH" 2>/dev/null || stat -c %Y "$GRAPH" 2>/dev/null)
  NOW=$(date +%s)
  AGE_DAYS=$(( (NOW - MTIME) / 86400 ))

  if [ "$AGE_DAYS" -gt 14 ]; then
    echo "GRAPHIFY_STALE: graph.json is ${AGE_DAYS} days old (threshold: 14 days)."
    echo "Consider running /graphify to refresh before spec work."
  else
    echo "GRAPHIFY_OK: graph.json is ${AGE_DAYS} days old — current."
  fi
fi
```

---

### Step 1h — Emit harness active confirmation

Print this message to confirm the harness is running and inject the verification protocol
into session context for the duration of this task.

---

## HARNESS ACTIVE — TASK: (use TASK value from Step 1a)

**GitHub Issue:** #ISSUE_NUMBER — ISSUE_TITLE
**Enforcement hooks installed:** `PreToolUse` (briefing gate) + `PostToolUse` (quality gate)

### VERIFICATION PROTOCOL (mandatory for this session)

You are now in **Spec Production mode**. These rules are in force until `/drew-product stop`.

**1. No pre-digested briefs to spec-writer.**
Before invoking the spec-writer Agent, you MUST invoke `code-fact-extractor` for every
technical identifier, return code, function name, class name, field name, and behavioral
claim in your research. Your inferences are hypotheses — not facts until the extractor
confirms them against source code.

**2. Citation file is the enforcement artifact.**
Write all extractor results to `.claude/task-progress/TASK-citations.jsonl` before
delegating to spec-writer. Each entry must have `"status": "VERIFIED"` and a `"source"`
with file path and line number. Entries with `"status": "INFERRED"` cannot appear in an
approved spec.

**3. PreToolUse hook will block briefs without citations.**
If you attempt to send a brief > 500 chars to spec-writer before the citation file exists
(or is non-empty), the hook will hard-block with exit code 2. This cannot be bypassed.

**4. PostToolUse hook runs citation verification after every Agent call.**
If the citation file is absent or has no VERIFIED entries after spec-writer completes,
the hook emits `DREW QUALITY GATE FAILED` to your context. Do not present the spec for
engineer approval while a quality gate failure is active.

**5. Spec must end with a `## Sources` section (Works Cited).**
Every factual claim must trace to at least one entry. Format:

```
## Sources

- `path/to/file.ext:LINE_START-LINE_END` (branch: BRANCH, commit: SHORT_SHA) — what this confirms
```

Rules: line numbers required, branch required, commit SHA required. Vague entries are invalid.
`/drew-eng` will verify every entry during adversarial review.

**6. ## Model Router is required.**
Count files in the spec's **Files to Change** table:
- ≥ 3 files OR ≥ 2 top-level modules → **Opus / Enterprise Architect**
- Architecture or design decision → **Opus**
- Shared contract change (API, DTO, hook signature) → **Opus**
- Otherwise → **Sonnet / General Engineer**

Write as a filled line: `**Decision:** Sonnet / General Engineer`

---

### Step 1i — Pre-spec grounding questions

Ask one at a time. Wait for each answer before asking the next.

1. **Intent check:** "In one sentence — what is this issue actually building? (Issue titles drift from real intent — this anchors the spec.)"

2. **Hidden constraints:** "Any constraints the issue doesn't mention? (Performance requirements, backwards-compat, demo time limits, related in-progress work.)"

3. **Blast radius:** "Are there other files or features likely to be affected beyond what the issue calls out? List them or say none."

---

### Step 1j — Invoke code-fact-extractor on all identifiers

Before delegating to spec-writer, extract all technical identifiers from the issue body and
grounding answers — function names, hook names, type names, file paths, API routes, component
names, CSS tokens — and invoke the **code-fact-extractor** agent with the full list.

This step is mandatory. Do not send a spec-writer brief until extractor results are in hand.

Print: `"Extracted N identifiers. Running code-fact-extractor..."`

---

### Step 1k — Delegate to /spec

Invoke `/spec GH-ISSUE_NUMBER` with:

**Issue content:** full issue title + body verbatim.

**Engineer Notes (from Step 1i):**
```
Intent: [engineer's answer to Q1]
Hidden constraints: [engineer's answer to Q2]
Blast radius: [engineer's answer to Q3]
```

**Extractor results (from Step 1j):** append full verification manifest.

**Required spec output — inject verbatim:**

> **REQUIRED — every spec must include these two final sections:**
>
> ### ## Model Router
> Count the Files to Change table. Apply the decision tree:
> - ≥ 3 files OR ≥ 2 top-level modules → **Opus / Enterprise Architect**
> - Architecture or design decision? → **Opus**
> - Shared contract change (API, DTO, hook signature)? → **Opus**
> - Otherwise → **Sonnet / General Engineer**
>
> Write as a filled line: `**Decision:** Sonnet / General Engineer`
>
> ### ## Sources
> List every file read to support a factual claim. Format per entry:
> `` `repo-relative/path/to/file.ext:LINE_START-LINE_END` (branch: BRANCH, commit: SHORT_SHA) — what this confirms ``
> Line numbers required. Branch required. Commit SHA (`git rev-parse --short HEAD`) required.

Spec saves to `docs/GH-ISSUE_NUMBER/SPEC.md`.

After spec approval, update the ACTIVE file phase:

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ACTIVE="${PROJECT}/.claude/task-progress/ACTIVE"
INIT_TIME=$(grep CXENG_INIT_TIME "$ACTIVE" | cut -d= -f2)
cat > "$ACTIVE" << EOF
CXENG_TICKET=GH-${ISSUE_NUMBER}
CXENG_PHASE=implement
CXENG_INIT_TIME=${INIT_TIME}
EOF
echo "Phase: spec → implement"
```

---

### Step 1l — Update GitHub Issue and print handoff

Add a comment to the GitHub issue:

```bash
gh issue comment "$ISSUE_NUMBER" \
  --body "Spec generated: \`docs/GH-${ISSUE_NUMBER}/SPEC.md\`

Run \`/drew-eng GH-${ISSUE_NUMBER}\` for adversarial claim verification, then \`/implement GH-${ISSUE_NUMBER}\` to build."
```

Print:

> "Spec approved and saved to `docs/GH-ISSUE_NUMBER/SPEC.md`. GitHub Issue #ISSUE_NUMBER updated.
>
> **Next:** Run `/drew-eng GH-ISSUE_NUMBER` for adversarial claim verification before implementation,
> or run `/implement GH-ISSUE_NUMBER` to go straight to building."

---

## Stop Flow

### Stop 1 — Verify backup exists

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TASK_DIR="${PROJECT}/.claude/task-progress"
ACTIVE="${TASK_DIR}/ACTIVE"
SETTINGS="${PROJECT}/.claude/settings.json"

if [ -f "$ACTIVE" ]; then
  . "$ACTIVE"
  TASK="${CXENG_TICKET}"
  BACKUP="${TASK_DIR}/${TASK}-settings-backup.json"
  echo "Stopping harness for: $TASK"
else
  echo "DREW_WARN: No ACTIVE file found. Harness may already be stopped."
  BACKUP=$(ls "${TASK_DIR}/"*-settings-backup.json 2>/dev/null | head -1)
  if [ -n "$BACKUP" ]; then
    echo "Found backup: $BACKUP"
  else
    echo "No backup found. Settings may already be clean."
  fi
fi
echo "BACKUP: ${BACKUP:-none}"
echo "SETTINGS: $SETTINGS"
```

### Stop 2 — Restore settings.json from backup

```bash
if [ -f "${BACKUP:-}" ]; then
  cp "$BACKUP" "$SETTINGS"
  echo "Settings restored from: $BACKUP"
else
  echo "DREW_ERROR: Backup file not found: ${BACKUP:-<no backup path>}"
  echo ""
  echo "Manual restore required. Remove these entries from settings.json:"
  echo '  PreToolUse entry with "_drew": true'
  echo '  PostToolUse entry with "_drew": true'
fi
```

### Stop 3 — Remove ACTIVE file

```bash
if [ -f "$ACTIVE" ]; then
  rm "$ACTIVE"
  echo "ACTIVE file removed."
fi
echo "Harness stopped."
```

### Stop 4 — Confirm settings clean

```bash
python3 - "$SETTINGS" << 'PYEOF'
import sys, json

path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

found = []
for event, matchers in cfg.get("hooks", {}).items():
    for entry in matchers:
        if entry.get("_drew"):
            found.append(f"{event}: {entry}")

if found:
    print(f"DREW_WARN: {len(found)} harness hook(s) still present after restore:")
    for f in found:
        print(f"  {f}")
    print("Backup restore may not have worked. Inspect settings.json manually.")
else:
    print("Settings clean: no harness hooks found.")
PYEOF
```

Print:

> "Harness stopped for **TASK**. Settings restored. Run `/drew-product <ISSUE_NUMBER>` to start a new session."
