---
name: review-spec
description: Run QA validation — check code against the spec and the original task. Use after implementation is complete, before opening a PR.
argument-hint: [TASK-ID]
---

# /review-spec — QA Validation Against Spec

Run the QA agent to validate code against the spec and the original task description.

## Usage

```
/review-spec <TASK_ID>
```

Or just `/review-spec` and the agent will ask for the task identifier.

## What It Does

1. Loads the three sources of truth:
   - Spec: `docs/<TASK>/SPEC.md`
   - Code: all files changed on this branch
   - Original task description (paste or provide)
2. Validates spec covers the task (Spec ↔ Task)
3. Validates code satisfies the spec (Code ↔ Spec)
4. Checks for scope violations (changes outside the spec)
5. Writes or updates tests based on the spec's test plan
6. Generates a QA validation report
7. Saves to `docs/<TASK_ID>/QA.md`

## Agent

This skill invokes the **QA Agent** (`agents/qa.md`).

## Output

A QA report at `docs/<TASK_ID>/QA.md` containing:
- Task ↔ Spec alignment check
- Spec ↔ Code validation (per acceptance criterion)
- Scope check (files changed vs spec)
- Tests written and results
- Verdict: PASS / FAIL / PASS WITH NOTES
- Specific findings with file:line references
