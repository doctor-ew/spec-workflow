---
name: unit-tests
description: Write unit tests for a completed ticket. Reads the spec's acceptance criteria and the changed files, then writes tests that cover each criterion. Never modifies implementation code.
argument-hint: <TICKET-XXX>
---

# /unit-tests — Write Unit Tests for a Ticket

Write unit tests that cover the acceptance criteria from the spec. This runs *after* `/implement` — the code is already there, this command adds test coverage without touching logic.

## Usage

```
/unit-tests TASK-218          # Write tests for a ticket
/unit-tests TASK-218 --dry-run  # Show what would be written, don't save
```

## Hard Rules

> **NEVER modify implementation files.** This command writes test files only. If a test requires a change to implementation code to pass, stop and flag it — do not make the change.

## What It Does

### Step 1 — Load inputs
1. Load the spec — check `docs/<TICKET>/SPEC.md` first, fall back to `docs/<TICKET>/SPEC.md`
2. If no spec found, stop: *"No spec found for <TICKET>. Run `/spec <TICKET>` first."*
3. Get the list of changed files: `git diff --name-only main...HEAD` (or the branch base)
4. Read each changed implementation file

### Step 2 — Assess existing coverage
For each acceptance criterion in the spec:
- Search for existing tests that exercise it
- Mark each criterion: **Covered** / **Partially covered** / **Not covered**

Report the coverage map before writing anything.

### Step 3 — Confirm scope
Present the coverage map and ask:
> "I found [N] uncovered and [M] partially covered criteria. I'll write tests for those. Proceed?"

Wait for confirmation before writing.

### Step 4 — Write tests
For each uncovered or partially covered criterion:
1. Identify the appropriate test file (colocated with the implementation, or in the existing `__tests__` / `Tests/` directory — follow the repo's pattern from CLAUDE.md)
2. Write focused unit tests:
   - One test per acceptance criterion (may have multiple assertions)
   - Use GIVEN/WHEN/THEN structure from the spec as the test description
   - Match the testing framework already in use (Jest, xUnit, NUnit — detect from existing test files)
   - No new dependencies — use the mocking/assertion libraries already present
3. Never create new test infrastructure — fit into what exists

### Step 5 — Run tests
Run the tests using the same runner as `run-all-tests`:
- `.sln` or `.csproj` → `dotnet test --filter <TestClass>`
- `bun.lock` → `bun test`
- Otherwise → `npm test`

If tests fail:
- If the failure reveals a genuine spec gap or implementation bug: report it, do not fix the implementation
- If the failure is in the test itself (wrong assertion, wrong mock): fix the test only, re-run

### Step 6 — Report

```
## Unit Tests Written — <TICKET>

Coverage before: [N covered / M total]
Coverage after:  [N covered / M total]

Tests written:
  ✅ AC-1: [description] → [test file:line]
  ✅ AC-3: [description] → [test file:line]
  ⚠️  AC-5: [description] → Partial — [reason]

Tests skipped (already covered):
  - AC-2, AC-4, AC-6

Files modified:
  - [test file path]

All tests: PASS
```

## Output

Test files added or updated in place alongside the implementation (or in the existing test directory — follow the repo pattern).

No separate report file is created unless `--save` is passed.

## Agent

This command invokes the **Unit Tests Agent** (`agents/unit-tests.md`).
