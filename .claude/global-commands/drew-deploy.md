---
name: drew-deploy
description: "Deployment Harness — requires /drew-qa PASS, conducts a structured 7-question preflight interview, generates PREFLIGHT.md and a deployment manifest, detects the target platform (Vercel, GH Pages, git push, Docker, etc.), and gates execution. Run /drew-deploy <TASK> [env] after /drew-qa PASS."
argument-hint: <TASK> [dev|staging|prod]
---

# /drew-deploy — Deployment Harness

Owns everything from QA hand-off to live deployment. Generates `PREFLIGHT.md` (the deployment
readiness snapshot) and `DEPLOY-{date}-{env}.md` (the ordered execution manifest). Nothing
executes until the engineer confirms all gates are green.

---

## Usage

```
/drew-deploy GH-12           — preflight + manifest for GH-12 (prompts for env)
/drew-deploy GH-12 prod      — targets production
/drew-deploy DEMO-PRD staging — targets staging
```

---

## Step 1 — Parse argument

Read `$ARGUMENTS`. Split on whitespace.

- `TASK` = first token
- `ENV_ARG` = second token (optional; prompt in Step 4 if missing)

If TASK empty:
> "Usage: /drew-deploy <TASK> [dev|staging|prod] — run after /drew-qa TASK passes."

---

## Step 2 — Resolve paths

```bash
PROJECT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TASK=$(echo "$ARGUMENTS" | awk '{print $1}')
ENV_ARG=$(echo "$ARGUMENTS" | awk '{print $2}')

SPEC="${PROJECT}/docs/${TASK}/SPEC.md"
REVIEW="${PROJECT}/docs/${TASK}/REVIEW.md"
DRIFT="${PROJECT}/docs/${TASK}/DRIFT.md"
QA="${PROJECT}/docs/${TASK}/QA.md"
PREFLIGHT="${PROJECT}/docs/${TASK}/PREFLIGHT.md"

TODAY=$(date +%Y-%m-%d)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
SHORT_SHA=$(git rev-parse --short HEAD)
BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || echo "main")

echo "PROJECT: $PROJECT"
echo "TASK:    $TASK"
echo "BRANCH:  $BRANCH"
echo "SHA:     $SHORT_SHA"
```

---

## Step 3 — Gate check: QA must pass

```bash
[ -f "$QA" ] || echo "QA_MISSING"
```

If QA.md missing:
> "No QA report found at `docs/TASK/QA.md`. Run `/drew-qa TASK` first."
Stop.

Read `$QA`. Extract the **Verdict** line.

If verdict = FAIL:
> "QA verdict is FAIL. Fix the blocking items and re-run `/drew-qa TASK` before deploying."
Stop.

If REVIEW.md exists, check for unresolved BLOCKs. If BLOCKs > 0:
> "REVIEW.md has N unresolved BLOCKs. Fix them or confirm they were accepted with reasoning before deploying."
Ask: "Proceed with unresolved BLOCKs? (yes / no)"
- No → stop.
- Yes → note accepted with risk in the manifest.

---

## Step 4 — Detect deployment platform

```bash
[ -f "${PROJECT}/vercel.json" ] || [ -f "${PROJECT}/.vercel/project.json" ] || \
  [ -f "${PROJECT}/vercel.ts" ] && echo "PLATFORM: vercel"

[ -f "${PROJECT}/.github/workflows/deploy.yml" ] || \
  [ -f "${PROJECT}/.github/workflows/cd.yml" ] && echo "PLATFORM: github-actions"

[ -f "${PROJECT}/Dockerfile" ] || [ -f "${PROJECT}/docker-compose.yml" ] && echo "PLATFORM: docker"

# GH Pages signal
grep -q '"homepage"' "${PROJECT}/package.json" 2>/dev/null && echo "PLATFORM: gh-pages"
```

Set `DEPLOY_PLATFORM` to the first match. If multiple match, list all and ask the engineer
which applies to this deployment.

If no platform detected: `DEPLOY_PLATFORM=manual` — engineer provides steps during interview.

---

## Step 5 — Structured interview (7 questions)

Ask one at a time. Wait for each answer.

**Q1: Confirm what we're deploying**
> "Confirming: branch `BRANCH`, commit `SHORT_SHA`, task `TASK`. Correct? (yes / describe change)"

**Q2: Target environment**
If `$ENV_ARG` is set: "Targeting `ENV_ARG`. Correct? (yes / change)"
Otherwise: "Target environment? (dev / staging / prod)"

Set `DEPLOY_ENV` and print: `DEPLOY_ENV set: $DEPLOY_ENV`

**Q3: What changed?**
> "Walk me through what changed — code, config, dependencies, migrations, feature flags.
> (I'll pre-fill from the diff; confirm or amend.)"

Pre-fill:
```bash
CHANGED=$(git diff --name-only "$BASE"...HEAD)
DEP_CHANGED=$(echo "$CHANGED" | grep -E 'package\.json|bun\.lock|requirements\.txt|go\.mod' || true)
ENV_ADDITIONS=$(git diff "$BASE"...HEAD | grep '^\+' | grep -oE '(process\.env|import\.meta\.env)\.[A-Z_]+' | sort -u || true)
MIGRATION_FILES=$(echo "$CHANGED" | grep -iE '(migration|migrate|schema|seed)' || true)
```

Present the pre-fill, then ask: "Anything to add or correct?"

**Q4: Migrations or schema changes?**
> "Any DB migrations, schema changes, or seed data required?"

If yes → validate:
- R1 — Files must be committed to source control (BLOCK if not)
- R2 — Each migration must have a paired rollback script (BLOCK if missing)
- R3 — Migrations touching shared schema → WARN: cross-team sign-off needed

**Q5: Config and environment variables**
> "New or changed environment variables, feature flags, or config values?"
Pre-fill `$ENV_ADDITIONS`. Engineer confirms or amends.

**Q6: Team roster**
> "Who's executing? Who's verifying? Who has rollback authority?"

**Q7: Dependencies, timing, and gotchas**
> "Cross-team dependencies, timing constraints, or deployment gotchas? (e.g. must deploy after DB migration, coordinate with mobile team)"

---

## Step 6 — Generate PREFLIGHT.md

Write to `$PREFLIGHT`:

```markdown
## Preflight Checklist

**Task:** TASK
**Date:** YYYY-MM-DD
**Branch:** BRANCH
**Commit:** SHORT_SHA
**Environment:** DEPLOY_ENV
**Platform:** DEPLOY_PLATFORM
**Spec:** docs/TASK/SPEC.md

---

### Changed Files
[list $CHANGED — grouped: new / modified / deleted]

### New Dependencies
[list $DEP_CHANGED, else "(none detected)"]

### Environment Variables
[list $ENV_ADDITIONS + Q5 answer, else "(none detected — verify manually)"]

### Migrations / Schema Changes
[list $MIGRATION_FILES + Q4 answer, else "(none detected)"]

### Risk Flags

**From REVIEW.md:**
[BLOCK count + WARN count, or "(none)"]

**From DRIFT.md:**
[SPEC_GAP + IMPL_GAP items, or "(none)"]

**From Q7 (engineer-supplied gotchas):**
[Q7 answer, or "(none)"]

---

### Pre-Deploy Gate Checklist
- [ ] QA verdict: [PASS / PASS WITH NOTES] — `docs/TASK/QA.md`
- [ ] REVIEW.md BLOCKs resolved (or accepted with reasoning)
- [ ] Drift verdict: ALIGNED (or DRIFT_DETECTED items accepted)
- [ ] Migrations committed to source control (R1)
- [ ] Migration rollback scripts present (R2)
- [ ] Env vars provisioned in DEPLOY_ENV
- [ ] Team roster confirmed
- [ ] Timing/dependency constraints satisfied (Q7)
- [ ] PR reviewed and approved (if applicable)

### Rollback Plan
[Describe steps based on DEPLOY_PLATFORM and what changed — specifics from Q3/Q4]
```

Print: `PREFLIGHT saved: docs/TASK/PREFLIGHT.md`

---

## Step 7 — Validate migration rules

If Q4 = yes:

| Rule | Status |
|------|--------|
| R1 — Migration files committed to source control | PASS / **BLOCK** |
| R2 — Paired rollback script exists for each migration | PASS / **BLOCK** |
| R3 — Shared schema change — cross-team sign-off | PASS / **WARN** |

If any BLOCK: print and stop:
```
DEPLOY BLOCKED — migration rules violated:
  [list]
Resolve before proceeding.
```

---

## Step 8 — Generate deployment manifest

```bash
MANIFEST="${PROJECT}/docs/${TASK}/DEPLOY-${TODAY}-${DEPLOY_ENV}.md"
```

Write to `$MANIFEST`:

```markdown
## Deployment Manifest

**Task:** TASK
**Date:** YYYY-MM-DD
**Environment:** DEPLOY_ENV
**Branch:** BRANCH
**Commit:** SHORT_SHA
**Platform:** DEPLOY_PLATFORM

---

### Pre-Deploy Gates
- [ ] QA: [PASS / PASS WITH NOTES] — `docs/TASK/QA.md`
- [ ] REVIEW.md BLOCKs: [N unresolved or "none"]
- [ ] Drift: [ALIGNED or accepted]
- [ ] Migrations: [validated or N/A]
- [ ] Env vars provisioned
- [ ] Team confirmed

---

### What Changed
[Q3 answer]

### Migrations (if any)
[Q4 answer + rule table]

### Config Changes
[Q5 answer, or "(none)"]

---

### Deployment Steps

#### Platform: Vercel
1. Confirm preview is healthy: `vercel inspect <preview-url>`
2. Promote to production: `vercel --prod` or via Vercel dashboard → Promote
3. Verify production URL returns expected response
4. Check Vercel logs for 5 min post-deploy
5. Smoke test: [key AC from spec]

#### Platform: GitHub Pages
1. Confirm branch `BRANCH` is up to date
2. Run build: `bun run build` / `npm run build`
3. Push / trigger deploy action: `git push origin BRANCH`
4. Monitor GitHub Actions: [repo]/actions
5. Verify published URL reflects changes
6. Smoke test: [key AC from spec]

#### Platform: GitHub Actions (CI/CD)
1. Merge PR into target branch
2. Monitor Actions run: [repo]/actions
3. Verify deployment conclusion = success
4. Smoke test deployed URL

#### Platform: Docker
1. Pull image: `docker pull [image]:[tag]`
2. Apply migrations in order (if applicable)
3. Roll out updated container
4. Health check endpoint
5. Smoke test

#### Platform: Manual (git push)
1. `git push origin BRANCH`
2. [Engineer-provided steps from Q3/Q7]
3. Verify deployed state

#### Engineer-supplied steps (Q7)
[Q7 answer — timing constraints, cross-team coordination, etc.]

---

### Validation Steps
1. Smoke test: [primary acceptance criterion from spec]
2. Check error monitoring for new errors post-deploy
3. Verify [specific behavior] in DEPLOY_ENV
4. Notify team of successful deploy

---

### Rollback Plan
[Steps matched to DEPLOY_PLATFORM:]

**Vercel:** Dashboard → Deployments → Promote previous deployment
**GH Pages:** `git revert HEAD && git push` or re-run workflow with prior tag
**GH Actions:** Revert merge commit, re-run workflow
**Docker:** Roll back to prior image tag; reverse migrations in reverse order
**Manual:** `git revert HEAD && git push`

Additional steps from Q4 (migrations): [reverse migration commands if applicable]
Notify: [executor notifies verifier and rollback authority — from Q6]

---

### Team Roster
| Role | Person |
|------|--------|
| Executor | [Q6] |
| Verifier | [Q6] |
| Rollback authority | [Q6] |

---

### Risk Flags
[QA PASS WITH NOTES items]
[REVIEW.md accepted BLOCKs]
[Drift SPEC_GAP + IMPL_GAP items]
[Q7 gotchas]

---

*All pre-deploy gates must be checked before executing.*
*Manifest generated by /drew-deploy.*
```

Print:
```
MANIFEST saved: docs/TASK/DEPLOY-DATE-ENV.md
PREFLIGHT:      docs/TASK/PREFLIGHT.md
```

---

## Step 9 — Final gate and execution prompt

Print the pre-deploy gate checklist from PREFLIGHT.md. Show each gate with current status.

Then ask:

```
══════════════════════════════════════════════════════════════════
TASK — Ready to Deploy?

  Environment:  DEPLOY_ENV
  Platform:     DEPLOY_PLATFORM
  Commit:       SHORT_SHA
  Manifest:     docs/TASK/DEPLOY-DATE-ENV.md

All gates above must be checked. Confirm deployment? (yes / no)
══════════════════════════════════════════════════════════════════
```

- **no** → "Deployment cancelled. Manifest saved for when you're ready."
- **yes** → print the platform deployment steps from Step 8 in order and begin executing them,
  pausing for engineer confirmation before any irreversible step (push, promote, migrate).

After each step, ask: "Step N complete — proceed to Step N+1? (yes / no / abort)"

On `abort`: stop and print the rollback plan.

On all steps complete:
```
══════════════════════════════════════════════════════════════════
TASK — Deployed ✓

  Environment: DEPLOY_ENV
  Commit:      SHORT_SHA
  Platform:    DEPLOY_PLATFORM

Monitor for errors. Rollback plan: docs/TASK/DEPLOY-DATE-ENV.md → Rollback Plan section.
══════════════════════════════════════════════════════════════════
```
