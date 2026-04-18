---
name: propagate-fix
description: Cherry-pick a fix from the current branch onto one or more target branches. Handles the branch-per-version workflow — pull latest, apply commits, run tests, leave ready for PR.
argument-hint: <target-branch> [target-branch-2 ...]
---

# /propagate-fix — Apply a Fix to Other Version Branches

When you've fixed a bug on one version branch and need to apply the same fix to other versions (e.g., 4.6.x → 4.7.x → development), this command handles the mechanical work: pulling latest, creating branches, cherry-picking commits, running tests.

## Usage

```
/propagate-fix Dev/main-next
/propagate-fix Dev/main-next Dev/Development
/propagate-fix Dev/main-next Dev/Development_4.8.X Dev/Development
```

## What It Does

### Step 1 — Identify fix commits
Detect the commits on the current branch that are not on its upstream/base:
```bash
git log --oneline <base>..HEAD
```
If the base branch cannot be detected automatically, ask the engineer: *"What branch did you branch from?"*

Show the commit list and ask:
> "I'll cherry-pick these [N] commit(s) onto each target branch:
> [list commits]
> Targets: [list targets]
> Proceed?"

**Wait for confirmation. Do not touch any branches until the engineer says yes.**

### Step 2 — For each target branch (in the order given)

1. **Fetch latest**
   ```bash
   git fetch origin <target-branch>
   ```

2. **Verify the bug still applies** *(advisory check)*
   Check whether the fix files exist on the target branch — if the target has already diverged significantly (e.g., files were renamed or deleted), flag it and ask how to proceed. Do not skip silently.

3. **Create a propagation branch**
   ```bash
   git checkout -b fix/<ticket>-propagate-<sanitized-target> origin/<target-branch>
   ```
   Where `<sanitized-target>` is the target branch name with `/` replaced by `-`.
   Example: `fix/TASK-218-propagate-Dev-main-next`

4. **Cherry-pick the fix commits**
   ```bash
   git cherry-pick <commit-hash> [<commit-hash-2> ...]
   ```

5. **Handle conflicts**
   If cherry-pick produces conflicts:
   - List conflicting files
   - For each conflict: show the diff and explain why it conflicted (context changed, file moved, etc.)
   - Ask the engineer to resolve — do not auto-resolve code conflicts
   - Once engineer resolves: `git cherry-pick --continue`

6. **Run tests**
   Detect and run:
   - `.sln` / `.csproj` → `dotnet test`
   - `bun.lock` → `bun test`
   - Otherwise → `npm test`

   If tests fail: report failures with `file:line`, stop. Do not proceed to the next target until this one is confirmed clean (or engineer explicitly says to continue).

7. **Report status for this target**
   ```
   ✅ fix/TASK-218-propagate-Dev-main-next
      Commits applied: 2
      Tests: PASS
      Ready for PR: git push origin fix/TASK-218-propagate-Dev-main-next
   ```

### Step 3 — Final summary

```
Propagation complete for TASK-218:

✅ Dev/main-next  → fix/TASK-218-propagate-Dev-main-next  (tests: PASS)
✅ Dev/Development        → fix/TASK-218-propagate-Dev-Development         (tests: PASS)

Next: review each branch manually, then create PRs.
The PR guardrail will ask you to confirm before each push.
```

## Rules

- **Never commits directly to the target branch.** Always creates a `fix/<ticket>-propagate-*` branch.
- **Never creates PRs automatically.** Leaves that to the engineer after review.
- **Never auto-resolves code conflicts.** Shows the conflict and waits.
- **Stops on test failure** unless the engineer explicitly says to continue anyway.
- **Processes targets sequentially** — one at a time, in the order given.

## Recovery

If something goes wrong mid-cherry-pick:
```bash
git cherry-pick --abort   # abandon this cherry-pick
git checkout -            # return to original branch
```

The command will suggest these cleanup steps if it encounters an unrecoverable state.
