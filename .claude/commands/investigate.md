---
name: investigate
description: Systematic root-cause debugging. Four phases — investigate, analyze, hypothesize, implement. Use when debugging errors, unexpected calculation results, failing tests, or any situation where the cause is unknown. Proactively suggest when the user reports broken behavior.
argument-hint: [description of the problem]
---

# /investigate — Systematic Root-Cause Debugging

**Iron Law: no fixes without root cause.** If you don't know why it's broken, you don't know that your fix will hold.

## Phase 1: Investigate

Before touching any code, gather evidence.

1. Read the error message or unexpected output in full — don't paraphrase it
2. Identify the exact file, line, and call site where the failure originates
3. Check recent changes: `git log --oneline -10` and `git diff HEAD~3`
4. For calculation engine issues: check the Cosmos config, the step definitions, and the data loader logs (`[DATALOADER_ERROR]` vs `[CONFIG_DATALOADER_ERROR]`)
5. For PostgreSQL issues: check the query, the schema placeholder resolution (`{schema:operational}` / `{schema:reference}`), and whether the table actually exists
6. For Azure Function issues: check Application Insights logs before making any code assumptions

**Do not form a hypothesis yet.** Just collect facts.

## Phase 2: Analyze

Review what you found. Ask:

- What is the system *actually* doing? (Not what it should do — what it *is* doing)
- What changed recently that could explain this?
- What assumptions did the original code make that may no longer be true?
- Is this a data problem, a logic problem, a config problem, or a wiring problem?

For calculation engine issues, distinguish:
- **Wrong result** → logic or config problem (NCalc expression, step formula, data profile mismatch)
- **No result / null** → data problem (missing reference data, FallbackValue triggered, negative cache hit)
- **Exception** → wiring problem (DI registration, missing service, schema not resolved)

## Phase 3: Hypothesize

State one specific hypothesis. Format:

```
Hypothesis: [The specific cause, in one sentence]
Evidence for: [What you observed that supports this]
Evidence against: [What could make this wrong]
How to verify: [The exact check that will prove or disprove it]
```

Do not skip straight to the fix. Run the verification first.

## Phase 4: Implement

Only after the hypothesis is confirmed:

1. Make the smallest change that fixes the root cause
2. Do not fix other things you notice — those are separate tickets
3. Verify the fix resolves the original failure
4. Add a test or check that would have caught this earlier

## Rules

- **Never fix a symptom.** If the calc returns 0, don't add a `?? defaultValue` — find out why it's returning 0.
- **One hypothesis at a time.** Don't scatter-fix across multiple possible causes.
- **Cite evidence for every claim.** "The NCalc expression is wrong" is not a root cause. "Line 14 of `calc-sp-exp-period-v1.json` uses `ResultName: 'credibility'` but the upstream step names it `credibility_factor`" is a root cause.
- **If you can't reproduce it, say so.** Don't guess at an intermittent failure — add logging first.
