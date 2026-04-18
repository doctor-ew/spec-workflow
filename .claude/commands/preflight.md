---
name: preflight
description: Generate a pre-deployment checklist for a task via a structured interview. Nothing deploys without a preflight. Run after /review confirms ready.
argument-hint: <TASK-ID>
---

# /preflight — Pre-Deploy Checklist

Conducts a structured interview and generates a deployment manifest. Does not execute any deployment steps — produces the checklist only.

## Usage

```
/preflight TASK-001     # Generate preflight manifest for a task
/preflight              # Ask for task ID
```

## What It Does

1. Reads the task and any existing spec/review docs for context
2. Conducts a 7-question interview in sequence
3. Validates any migration or data scripts if present
4. Generates a deployment manifest with ordered steps, validation, and rollback
5. Saves to `docs/<TASK>/preflight-<date>-<env>.md`

## The Seven Questions

| # | Captures |
|---|---------|
| 1 | What are we deploying? (task, branch, PR) |
| 2 | Target environment? (local / staging / prod) |
| 3 | What changed? (code, DB migrations, config, packages) |
| 4 | Migration / data scripts? (paths in source control, rollback scripts) |
| 5 | Config changes? (env vars, feature flags, secrets) |
| 6 | Team roster? (executor, verifier, rollback authority) |
| 7 | Cross-team dependencies or special considerations? |

## Script Validation Rules

If migration or data scripts are mentioned, these are validated before the manifest is written:

| Rule | Severity | Condition |
|------|----------|-----------|
| R1 | BLOCK | Scripts must be committed to source control — no ad-hoc |
| R2 | BLOCK | Every destructive script must have a paired rollback |
| R3 | WARN | Scripts touching shared data require sign-off |

A BLOCK halts manifest generation until resolved.

## Agent

This command invokes the **Preflight Agent** (`agents/preflight.md`).

## Output

Saved to `docs/<TASK>/preflight-<date>-<env>.md`:

- Pre-deploy gates checklist
- Ordered deployment steps
- Validation steps
- Rollback plan
- Team roster
- Risk flags from interview
