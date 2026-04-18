---
name: review
description: Unified review — runs spec check and code quality (DRY/SOLID/ACID/CoC) in parallel and gates the ticket into ready-to-ship when clean.
argument-hint: [TASK-ID | path/to/file.ts | (none = branch diff)]
---

# /review — Unified Code Review

Runs spec check and code quality review, merges findings into a single report.

## Usage

```
/review TASK-001           # Unified review of a task (spec + code quality)
/review src/lib/api.ts     # Code quality review of a specific file (no spec check)
/review                    # Code quality review of everything changed on this branch
```

## What It Does (Task Mode)

### Review scope

Before running any checks, scan changed file paths for security signals:
```
auth / token / credential / secret / key / password / sas / hmac / signing / jwt / permission / role / claim
```

| Change type | Agents invoked |
|---|---|
| Bugfix / refactor / feature | `code-reviewer` only |
| Auth / secrets / security-sensitive path | `code-reviewer` + `security-auditor` in parallel |

If security signals are detected, announce: *"Security-sensitive files detected — running code-reviewer and security-auditor in parallel."*

### Steps

1. Load inputs:
   - Spec: `docs/<TASK>/SPEC.md`
   - QA report: `docs/<TASK>/QA.md` (if exists)
   - Changed files on this branch
2. **Spec check** — did the implementation satisfy the acceptance criteria and stay in scope?
3. **Code quality** — DRY, SOLID, ACID, CoC lenses against all changed files
4. Merge findings into a single report
5. Save to `docs/<TASK>/REVIEW.md`
6. If verdict is APPROVE with no BLOCKs → ask the engineer if ready to ship

## Completion Gate

When verdict is APPROVE with no BLOCKs:

> "Review passed with no blockers. Ready to run preflight and ship?"

| Response | Action |
|----------|--------|
| Yes / ready | Launch `/preflight <TASK>` |
| No / not yet | No action — fix what's needed and re-run |

If BLOCKs exist: no prompt. Fix the BLOCKs and re-run.

## Report Format

```
/review result: APPROVE | REQUEST CHANGES | REJECT

Spec check:    PASS | FAIL
Code quality:  APPROVE | REQUEST CHANGES | REJECT

BLOCKs (must fix before merge)
• [file:line] Description

WARNs (should fix)
• [file:line] Description

NOTEs (worth discussing)
• Description

Recommended actions:
1. ...

Full report: docs/<TASK>/REVIEW.md
```

## Agent

This command invokes the **Code Reviewer Agent** (`agents/code-reviewer.md`).

## Output

| Target | Report saved to |
|--------|----------------|
| `/review TASK-ID` | `docs/TASK-ID/REVIEW.md` |
| `/review` (branch) | `docs/<branch-name>/REVIEW.md` |
| `/review path/to/file` | Inline only (no file save unless asked) |

## The Full Task Lifecycle

| Command | What happens |
|---------|-------------|
| `/spec TASK-ID` | Spec approved → progress tracker created |
| `/review TASK-ID` | Review passes → engineer confirms ready → `/preflight` launches |
| `/preflight TASK-ID` | Deployment manifest generated — safe to ship |
