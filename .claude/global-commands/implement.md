---
name: implement
description: Orchestrate full spec-driven implementation — branch, design, plan, build, test, hand off to /review. No spec = no build. Never commits or creates a PR.
argument-hint: <TICKET-XXX>
---

# /implement — Spec-Driven Implementation

Orchestrates the full implementation cycle for a ticket that already has an approved spec. The engineer stays in control at every decision point — branch name, solution choice, plan approval.

## Usage

```
/implement TASK-001
/implement TASK-042
```

---

## Step 0 — Get ticket and check spec

Accept the ticket number as an argument, or ask for it.

**Check for spec:**
```
docs/<TICKET>/SPEC.md
```

**If no spec exists — hard stop:**
> "No spec found for <TICKET>. Run `/spec <TICKET>` first. No build without a spec."

Do not proceed. Do not offer to generate a spec inline. Stop here.

**If spec exists:** load it fully. Extract:
- Acceptance criteria count (number of numbered items in `## Acceptance Criteria`)
- Files to change count (rows in `### Files to Change` table)
- Ticket type (Bug vs Feature — check `**Type:** Bug` in frontmatter)

---

## Step 1 — Suggest a branch name

Based on the ticket number and spec title, suggest a branch name:

| Ticket type | Pattern |
|---|---|
| Feature / Task | `feature/task-XXX-short-slug` |
| Bug | `bugfix/task-XXX-short-slug` |

The slug is 3–5 words from the spec title, lowercase, hyphenated. Drop articles and filler words.

Present the suggestion and ask:
> "Branch: `feature/task-001-unified-code-review` — OK, or use a different name?"

Wait for confirmation. Do not create the branch — the engineer runs `git checkout -b` themselves, or confirm they want Claude to run it.

If engineer confirms Claude should create it:
```bash
git checkout -b <branch-name>
```

---

## Step 2 — Present 2–3 solution approaches

Read the spec's `## Solution` section and the relevant code. Present **2 or 3 distinct approaches** — not variations of the same approach.

Format each approach as:

```
### Approach A — [Name]
[2–3 sentences describing the approach]
**Pros:** ...
**Cons:** ...
**Effort:** Quick (<1h) | Short (1–4h) | Medium (1–2d) | Large (3d+)
```

Always include one conservative approach (minimal change) and one that follows the spec most directly. A third is optional if genuinely different.

Ask: *"Which approach do you want to use — A, B, or C?"*

Wait for the engineer's choice before proceeding.

---

## Step 3 — Detailed implementation plan

Based on the chosen approach, write a numbered implementation plan:

```
## Implementation Plan

### Blast Radius
- Files: [every file to be created or modified]
- Modules: [every module/project affected]
- Cross-team: [shared contracts, APIs, DTOs — flag loudly if any]

### Sequence
1. [First change — why it goes first]
2. [Second change]
...

### Risks
- [What could go wrong and how to handle it]

### Effort estimate
[Quick / Short / Medium / Large]
```

Ask: *"Does this plan look right? Any changes before I start?"*

Wait for explicit approval — "yes", "looks good", "go ahead", or similar. Do not start implementing on vague responses.

---

## Step 4 — Create tasks and progress file

Once the plan is approved:

**Create a task for each implementation step** using TaskCreate. Include tasks for:
- Each numbered step in the implementation plan
- "Run tests"
- "Hand off to /review"

**Write a progress file** to `.claude/task-progress/<TICKET>.md`:

```markdown
# <TICKET> — Implementation Progress

**Started:** <YYYY-MM-DD>
**Branch:** <branch-name>
**Spec:** docs/<TICKET>/SPEC.md
**Approach:** [chosen approach name]

## Steps
- [ ] [Step 1]
- [ ] [Step 2]
...
- [ ] Run tests
- [ ] /review <TICKET>
```

Update this file as steps complete (check off boxes).

---

## Step 5 — Implement

**Route to the appropriate agent based on programmatic thresholds — not judgment:**

| Condition | Agent |
|---|---|
| AC count ≥ 10 OR files ≥ 5 OR spans multiple modules | Architect agent |
| Everything else | Engineer agent |

Tell the engineer which agent is being used and which threshold triggered the routing.

**If the invoked agent returns `## AGENT BLOCKED`:** surface the full block to the engineer — do not suppress it or attempt to continue. The block contains the required action.

**Rules for both agents:**
- Follow the spec's acceptance criteria as the checklist — nothing more, nothing less
- Follow the repo's CLAUDE.md conventions
- If a file discovered during implementation is not in the spec's "Files to Change" table, **stop and flag it** before touching it
- If the spec is discovered to be incomplete or wrong, **stop and flag it** — do not improvise

As each step completes, update the task status and check off the step in `.claude/task-progress/<TICKET>.md`.

---

## Step 6 — Run tests

When implementation is complete, invoke the **run-all-tests** agent:

> "Implementation complete. Running tests now."

The agent detects the project type (dotnet / bun) from the repo's CLAUDE.md and runs the appropriate command.

**If run-all-tests returns `## AGENT BLOCKED`:** surface the block to the engineer — tests could not run at all. Do not loop.

**If tests fail:**
- Read the failure output
- Fix the failing tests (staying within spec scope)
- Re-invoke run-all-tests
- After 3 failures on the same test — **hard escalate**: present the failure to the engineer and stop the loop. Do not attempt a 4th fix. Repeated attempts without new information are not progress.

**If tests pass:**
- Mark "Run tests" task complete
- Update progress file

---

## Step 7 — Hand off

When all tasks are complete and tests are green:

1. Mark all tasks complete
2. Mark all steps in progress file complete
3. Present a summary:

```
## Implementation complete — CR-XXX

### What was built
[2–3 sentence summary of what changed]

### Files modified
| File | What changed |
|------|-------------|
| path/to/file | description |

### Tests
✅ All passing

### Next step
Run: /review CR-XXX
```

**Do not create a commit. Do not push. Do not open a PR.**
The engineer runs `/review <TICKET>` when ready.

---

## Rules

- **No spec = no build.** This is a hard stop, not a soft warning.
- **Never commit or push.** That is the engineer's decision after `/review` passes.
- **Never touch files not in the spec.** Flag and ask before any out-of-scope change.
- **Never skip the approval gates.** Branch confirmation and plan approval are mandatory.
- **If the spec is wrong, stop.** Do not improvise a fix. Flag the gap and let the engineer decide whether to update the spec first.
- **Escalate on repeated test failures.** Three failures on the same test = engineer involvement, not more guessing.
