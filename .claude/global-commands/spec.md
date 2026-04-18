---
name: spec
description: Generate a technical specification from a task or ticket. Auto-detects Story, Bug, or Arcade mode. Task first, spec second, code third.
argument-hint: <task-id-or-description>
---

# /spec — Generate a Spec

Generate a technical specification from a task or ticket description. The spec becomes the contract for implementation — no code without a spec.

> **HARD STOP — SPEC PHASE IS READ-ONLY**
> Do NOT write code, edit implementation files, run git commands, or make any changes to the codebase during this command. The spec phase ends when the engineer approves the spec document. Nothing else.

## Usage

```
/spec <TASK_ID>          # auto-detect mode
/spec <TASK_ID> --quick  # force Arcade mode
/spec <TASK_ID> --full   # force full Story spec (skip auto-detect)
/spec <TASK_ID> --force  # regenerate even if spec already exists
```

Or just `/spec` and the agent will ask what you're working on.

## Providing the Task

Paste or describe what needs to be built:
- A task ID from Linear, GitHub Issues, Jira, or any other system
- A copied task description
- A plain English description of the work

If you have an issue URL or can paste the task content directly, that works too.

## What It Does

### Step 1 — Check for existing spec

Check for an existing spec at `docs/<TASK_ID>/SPEC.md`.

**If no spec exists:** proceed to generate one.

**If a spec exists:**

| Condition | Action |
|-----------|--------|
| Task unchanged since spec written | "Spec is current. Show it and confirm before implementing." |
| Task updated after spec | "⚠️ Spec may be stale. Show what changed, ask: Update spec or proceed anyway?" |
| Engineer ran `/spec` with `--force` | Regenerate unconditionally |

Never silently overwrite an approved spec.

### Step 2–5 — Generate
1. Reads the task description
2. Reads the repo's CLAUDE.md for conventions
3. **Detects Story, Bug, or Arcade mode** (see below)
4. Asks clarifying questions if the task is vague
5. Generates a structured spec using the Spec Writer agent
6. Saves to `docs/<TASK_ID>/SPEC.md` (creates directory if needed)
7. Presents for engineer review and approval

## Modes

```mermaid
flowchart TD
    Task[Read task] --> BugCheck{Bug description\nor bug keywords?}
    BugCheck -- Yes --> Bug[🐛 Bug Mode]
    BugCheck -- No --> ArcadeCheck{Small task,\nchore, or --quick?}
    ArcadeCheck -- Yes --> Offer[Offer Arcade\n'--full to override']
    Offer --> ArcadeApproved{Engineer\naccepts?}
    ArcadeApproved -- Yes --> Arcade[🕹 Arcade Mode]
    ArcadeApproved -- No / --full --> Story[📋 Story Mode]
    ArcadeCheck -- No --> Story
```

| Mode | Trigger | What you get |
|------|---------|-------------|
| **🕹 Arcade** | Small task, chore/config type, or `--quick` | Lite spec: Problem + Constraints + Files + AC only |
| **📋 Story** | Feature, refactor, spike, or ambiguous task | Full spec with all sections |
| **🐛 Bug** | Bug description or bug keywords in title | Deviation doc — engineer defines correctness, agent expands edge cases |

## On Approval

When the engineer approves the spec, the agent:
1. Writes a progress tracker to `.claude/task-progress/<TASK_ID>.md`
2. Prompts: *"Spec approved. Run `/implement <TASK_ID>` to start building."*

## Agent

This skill invokes the **Spec Writer** agent (`agents/spec-writer.md`).

## Output

A spec file at `docs/<TASK_ID>/SPEC.md`.

**Story spec contains:**
- Problem statement
- Technical constraints
- Solution design
- Files to change
- Acceptance criteria (GIVEN/WHEN/THEN)
- Risks, dependencies, test plan, sources

**Bug spec contains:**
- Traces To (link to original story spec)
- Current behavior (buggy)
- Expected behavior (engineer-defined)
- Root cause hypothesis (labeled, optional)
- Acceptance criteria (engineer-approved)
- Edge cases and test scenarios (agent-expanded)
