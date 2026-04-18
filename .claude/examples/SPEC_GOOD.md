# SPEC: ACME-1234 — Fix Policy Export CSV Column Mismatch

**Ticket:** ACME-1234
**Date:** 2026-03-20
**Author:** Jane Smith (via Spec Writer Agent)
**Status:** Draft

---

## Problem

The policy export CSV on the Admin Dashboard produces a file where the `EffectiveDate` and `ExpirationDate` columns are swapped. Users download the CSV, import it into their quoting systems, and get the wrong dates on 100% of records. This was reported by 3 clients (ACME Corp, Bravo Inc, Charlie LLC) on 2026-03-18.

**Reproduction:**
1. Navigate to Admin Dashboard → Policies → Export
2. Select any date range with 10+ policies
3. Click "Export CSV"
4. Open the CSV — column F (`EffectiveDate`) contains expiration dates, column G (`ExpirationDate`) contains effective dates

**Impact:** All clients using the CSV export are affected. Manual workaround: swap columns in Excel after download.

## Technical Constraints

- **Framework:** React 18 frontend, .NET 8 Azure Functions API
- **Export endpoint:** `GET /api/policies/export` in `PolicyFunctions.cs`
- **CSV generation:** Uses `CsvHelper` library (v33.x)
- **Existing pattern:** Column mapping is defined in `PolicyCsvMap.cs` using `CsvHelper.Configuration`
- **No breaking changes to column order** — downstream consumers (client quoting systems) expect the current header names. Only the data mapping is wrong, not the headers.

## Solution

### Approach

The column headers are correct but the property mapping in `PolicyCsvMap.cs` has `EffectiveDate` mapped to `ExpirationDate` and vice versa. Swap the two property references in the map class.

### Files to Change

| File | Change | Why |
|------|--------|-----|
| `src/Functions/Maps/PolicyCsvMap.cs` | Swap `EffectiveDate` ↔ `ExpirationDate` property references in column mapping | Root cause — properties are mapped to wrong columns |
| `src/Functions.Tests/Maps/PolicyCsvMapTests.cs` | Add test asserting correct column-to-property mapping | Prevent regression |

### What This Does NOT Change

- Column headers (they are already correct)
- Column order (downstream consumers depend on it)
- Any other export (Claims, Billing, etc.)
- The `Policy` model or database schema

## Acceptance Criteria

1. GIVEN a user exports policies as CSV WHEN they open the file THEN column F (`EffectiveDate`) contains the policy's effective date, not the expiration date
2. GIVEN a user exports policies as CSV WHEN they open the file THEN column G (`ExpirationDate`) contains the policy's expiration date, not the effective date
3. GIVEN the fix is deployed WHEN a downstream system imports the CSV THEN no column order or header changes break the import (backwards compatible)

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Other column mappings may also be wrong | Low | High | Audit all columns in `PolicyCsvMap.cs` during fix — report findings but don't fix in this ticket |
| Clients may have built workarounds (manual column swap) that break when we fix it | Medium | Medium | Notify affected clients (ACME, Bravo, Charlie) before deployment with expected fix date |

## Dependencies

- [ ] External: Notify ACME Corp, Bravo Inc, Charlie LLC before deploying the fix
- [ ] Internal: None — isolated fix

## Test Plan

- **Unit test:** Assert `PolicyCsvMap` maps `EffectiveDate` property to column F and `ExpirationDate` property to column G
- **Integration test:** Generate a CSV via the endpoint with known test data, parse the output, verify column F and G values match the source `Policy` records
- **Manual verification:** Export CSV from Admin Dashboard dev environment, open in Excel, confirm dates are in correct columns

---

> **Why this is good:**
>
> - **Specific problem.** Exact columns, exact behavior, exact clients affected, exact reproduction steps.
> - **Clear constraints.** Framework, library, existing patterns, backwards compatibility requirement.
> - **Minimal solution.** Two files, one root cause, no scope creep.
> - **Testable acceptance criteria.** Each one is GIVEN/WHEN/THEN. You can write a test for each.
> - **"What This Does NOT Change" prevents scope creep.** The engineer won't "also fix" other exports.
> - **Risks are real and actionable.** Client workaround breakage is a real risk with a real mitigation (notify them).
> - **Test plan has three levels.** Unit, integration, manual — each checking something specific.
>
> An engineer reading this spec can start coding in minutes. A QA agent can validate the implementation against each criterion. There's no ambiguity about what "done" looks like.
