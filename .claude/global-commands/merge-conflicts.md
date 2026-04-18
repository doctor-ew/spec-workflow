---
name: merge-conflicts
description: Cross-platform git merge conflict resolution — script phases for mechanical work, merge-resolver agent for judgment. Auto-detects Boss Rush (no spec) and creates follow-up task. Never auto-commits.
argument-hint: [--theirs-wins | --ours-wins] [--merge-base <sha>] [--planning-dir <path>]
---

# /merge-conflicts — Structured Merge Conflict Resolution

Orchestrates a 10-phase workflow to resolve an in-progress git merge. Scripts handle mechanical work; the `merge-resolver` agent handles judgment calls. Never commits. At the end: you commit.

## Usage

```
/merge-conflicts                          # auto-detect merge base, THEIRS wins (default)
/merge-conflicts --theirs-wins            # explicit: MERGE_HEAD / Dev branch wins on conflicts
/merge-conflicts --ours-wins             # explicit: HEAD / RC branch wins on conflicts
/merge-conflicts --merge-base abc123     # supply merge base SHA manually
/merge-conflicts --planning-dir ./docs/merge  # custom planning output directory
/merge-conflicts --boss-rush             # explicitly acknowledge no spec exists
```

### Boss Rush

If no spec is found for the ticket on the current branch, the merge-resolver agent automatically enters **Boss Rush mode**: it resolves conflicts normally, then appends a spec-debt notice to the PR description. Pass `--boss-rush` to confirm this explicitly and skip the prompt.

## Flags

| Flag | Default | Meaning |
|------|---------|---------|
| `--theirs-wins` | ✓ default | MERGE_HEAD (branch being merged in) wins on version conflicts |
| `--ours-wins` | — | HEAD (current branch) wins on version conflicts |
| `--merge-base <sha>` | auto-detected | Override merge base SHA |
| `--planning-dir <path>` | `./merge-planning` | Where to write ConflictList.md, Phase files, Decisions |
| `--batch-start <n>` | 1 | Start package resolution at file N (for large batches) |
| `--batch-size <n>` | 15 | Max files per package resolution batch |

---

## Workflow

### Phase 0 — Platform detect + validation

1. Detect platform:
   - Mac/Linux: `python3 --version` → use `scripts/merge/*.py`
   - Windows: `pwsh -version` → use `scripts/merge/*.ps1`
2. Confirm we are in a git repo with a merge in progress:
   ```bash
   git status --porcelain | grep -E "^(UU|AA|DD|AU|UA|DU|UD)"
   ```
   If no conflicts found, stop: *"No merge conflicts detected. Nothing to do."*
3. Resolve merge base:
   - If `--merge-base` supplied: use it
   - Otherwise: `git merge-base HEAD MERGE_HEAD`
   - If that returns multiple lines: warn *"Criss-cross merge detected — multiple merge base candidates. Supply `--merge-base <sha>` explicitly."* and stop.
4. Resolve `--planning-dir` (default: `./merge-planning`)
5. Create planning dir if it doesn't exist
6. Set `WIN_FLAG` = `--theirs-wins` or `--ours-wins` based on args (default `--theirs-wins`)

---

### Phase 1 — Conflict list

**Script:** `get_conflict_list` (Python) or `Get-ConflictList` (PowerShell)

```bash
# Mac
python3 scripts/merge/get_conflict_list.py --repo . --planning-dir <planning-dir>

# Windows
pwsh scripts/merge/Get-ConflictList.ps1 -RepoPath . -OutputPath <planning-dir>/ConflictList.md
```

Output: `<planning-dir>/ConflictList.md`

Show the summary table to the engineer. Continue automatically.

---

### Phase 2 — Classification

**Script:** `get_conflict_classification` / `Get-ConflictClassification`

```bash
# Mac
python3 scripts/merge/get_conflict_classification.py --repo . --planning-dir <planning-dir>

# Windows
pwsh scripts/merge/Get-ConflictClassification.ps1 -RepoPath . -OutputPath <planning-dir>/ConflictClassification.md
```

Output: `<planning-dir>/ConflictClassification.md`

Show the summary table. Continue automatically.

---

### Phase 3 — Build phase files

**Script:** `build_phase_files` / `Build-PhaseFiles`

```bash
# Mac
python3 scripts/merge/build_phase_files.py --planning-dir <planning-dir>

# Windows
pwsh scripts/merge/Build-PhaseFiles.ps1 -ClassificationPath <planning-dir>/ConflictClassification.md -OutputDir <planning-dir>
```

Output: `Phase-1-Packages.md` through `Phase-6-BothAdded.md` in `<planning-dir>/`

Show file counts per phase. Continue automatically.

---

### Phase 4 — Auto-resolve packages (dry-run first)

**Script:** `resolve_package_conflicts` / `Resolve-PackageConflicts`

**Always run dry-run first:**
```bash
# Mac
python3 scripts/merge/resolve_package_conflicts.py --repo . --planning-dir <planning-dir> --merge-base <sha> <win-flag> --dry-run

# Windows
pwsh scripts/merge/Resolve-PackageConflicts.ps1 -RepoPath . -PlanningDir <planning-dir> -MergeBase <sha> -DryRun
```

Show the dry-run summary to the engineer. Ask:

> "Phase 4 dry-run complete. Ready to apply these resolutions? [yes/no]"

If yes: run live (same command without `--dry-run`).
If no: *"Phase 4 skipped. You can resolve packages manually and re-run."*

After live run: show count of resolved vs flagged files.

---

### Phase 5 — Validate resolved

**Script:** `validate_resolved` / `Validate-Resolved`

```bash
# Mac
python3 scripts/merge/validate_resolved.py --repo . --planning-dir <planning-dir>

# Windows
pwsh scripts/merge/Validate-Resolved.ps1 -RepoPath . -PhaseFile <planning-dir>/Phase-1-Packages.md
```

If any issues: show them. Do not proceed past Phase 5 with lingering markers.

---

### Phase 6 — Flagged diffs (merge-resolver agent)

Invoke the **merge-resolver** agent for **Sub-task A — Flagged diff review**:

> "Invoking merge-resolver agent for flagged diffs in `<planning-dir>/FlaggedDiffs/`."

Pass to the agent:
- Planning dir path
- Merge base SHA
- `WIN_FLAG`
- Instruction: "Sub-task A — review all files in FlaggedDiffs/, write D-NNN decisions, update Phase-1-Packages.md status"

Wait for agent to complete. Show count of `[x]` and remaining `[!]` items.

---

### Phase 7 — Code conflicts (merge-resolver agent)

Invoke the **merge-resolver** agent for **Sub-task B — Code conflict resolution**:

> "Invoking merge-resolver agent for Phase-2-Code.md."

Pass to the agent:
- Planning dir path
- Repo path
- `WIN_FLAG`
- Instruction: "Sub-task B — resolve all `[ ]` files in Phase-2-Code.md, no conflict markers may remain on [x] files"

**Important:** The agent proposes resolutions. Before writing any resolved file, display the proposed resolution and ask:

> "Proposed resolution for `<file>`. Apply? [yes/no/skip]"

Wait for engineer confirmation per file. Apply only on yes.

---

### Phase 8 — Both-added (merge-resolver agent)

Invoke the **merge-resolver** agent for **Sub-task C — Both-added resolution**:

> "Invoking merge-resolver agent for Phase-6-BothAdded.md."

Pass to the agent:
- Planning dir path
- Repo path
- Instruction: "Sub-task C — resolve all `[ ]` files in Phase-6-BothAdded.md"

Same confirmation gate as Phase 7.

---

### Phase 9 — Pipeline / Config / Other (merge-resolver agent)

Invoke the **merge-resolver** agent for Phase 3 (Pipelines), Phase 4 (Config), and Phase 5 (Other) files:

> "Invoking merge-resolver agent for pipeline, config, and other conflicts."

Same confirmation gate as Phase 7. These categories always require human judgment — the agent proposes, the engineer decides.

---

### Phase 10 — Final validate

Run `validate_resolved` across all phase files:

```bash
# Mac
python3 scripts/merge/validate_resolved.py --repo . --planning-dir <planning-dir> --all-phases

# Windows
pwsh scripts/merge/Validate-Resolved.ps1 -RepoPath . -PlanningDir <planning-dir> -AllPhases
```

If zero remaining markers:

> "✅ All phases complete — zero conflict markers remain. Run `git commit` to finalise the merge."

If markers remain: list them. Do not prompt for commit.

---

## Rules

- **Never commit.** This command ends at *"Run `git commit`..."*. The engineer commits.
- **Never auto-apply code resolutions.** Phases 7–9 require per-file engineer confirmation.
- **Dry-run before live.** Phase 4 always shows a dry-run summary before asking to apply.
- **Stop on missing planning dir content.** If a phase file is missing, stop and tell the engineer to re-run the preceding phase.
- **Never use Codex or GPT delegation tools.** The merge-resolver agent is the judgment layer — invoke it, not external models.
- **Platform script must match.** Never call `.py` on Windows or `.ps1` on Mac.
