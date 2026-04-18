# SPEC: ACME-1234 — Fix the Export

**Ticket:** ACME-1234
**Date:** 2026-03-20
**Status:** Draft

---

## Problem

The export is broken. Users are complaining.

## Solution

Fix the export so it works again. Maybe the CSV formatting is wrong or something.
Look at the export code and figure it out.

## Acceptance Criteria

1. The export should work correctly
2. It should be fast
3. No bugs

## Test Plan

Test it manually.

---

> **Why this is bad:**
>
> - **Vague problem.** Which export? What's broken? What do users see? No reproduction steps.
> - **No constraints.** What framework? What format? What size data? Any performance targets?
> - **"Figure it out" solution.** The engineer is guessing at the root cause before starting.
> - **Untestable acceptance criteria.** "Should work correctly" — how? What does "correctly" look like? "Fast" — how fast? Compared to what?
> - **No files identified.** Where is the export code? What does it touch?
> - **No risks.** What if fixing the CSV format breaks downstream consumers?
> - **"Test it manually" is not a test plan.** What do you click? What do you check? How do you know it passed?
>
> This spec creates false confidence. Someone could "complete" this ticket and ship something that doesn't solve the actual problem, because the actual problem was never defined.
