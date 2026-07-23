# Specification: Evaluation and Coverage

> **Spec type:** Evaluation
> **Status:** Draft
> **Decision owner:** Product owner
> **Primary executor:** Engineer plus QA
> **Last updated:** 2026-07-22

---

## 1. Why this spec exists

The product should be steered by specifications that can be checked constantly.
This spec defines how the team will know whether the implementation matches the
product and where the gaps still are.

## 2. Outcome statement

**After this spec is executed:**
Every core product promise has an evaluation path through golden scenarios, negative legality tests, and coverage reviews tied back to the spec system.

**Verification method:**
Map each core spec to executable tests, scenario fixtures, or structured reviews,
then confirm no anchor promise exists without an evaluation hook.

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| The specs should act as success criteria and full product context | `[Validated]` | Direct user goal |
| The specs should support ongoing evaluations to discover missing work | `[Validated]` | Direct user goal |
| Strict legality is valuable partly because it helps verify rules correctness | `[Validated]` | Direct user answer |

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| S-1 | Golden scenario library | Canonical legal journeys |
| S-2 | Negative scenario library | Canonical illegal journeys and blocked choices |
| S-3 | Coverage matrix | Which spec claims are tested, reviewed, or still missing |
| S-4 | Drift detection | Identify when canon, implementation, and explanations diverge |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| X-1 | Ad hoc testing guided only by memory | Insufficient for a rules product |
| X-2 | Manual QA with no traceability to specs | Does not satisfy the user's goal |
| X-3 | Metrics detached from explicit user journeys | Weak signal for rules correctness |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| Engineer | Build against clear success checks | Primary executor |
| QA | Verify journeys and rules behavior | Secondary executor |
| Product owner | See what is specified, covered, and still unknown | Decision role |

## 7. Flow / state changes

1. Each bounded spec defines acceptance criteria.
2. Evaluation spec turns those criteria into scenarios, tests, or review checklists.
3. New feature work must attach to an existing spec or create a new one.
4. Coverage matrix identifies gaps between product intent and implementation evidence.

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | Every anchor workflow spec has at least one golden scenario and one negative scenario. | `[Assumed: verify]` |
| AC-2 | Behavioral | Level-up completion is not considered done until in-scope class progression scenarios pass. | `[Validated]` |
| AC-3 | Behavioral | The team can identify which spec or acceptance criterion any core test is validating. | `[Assumed: verify]` |
| AC-4 | Negative | Product work is not accepted solely because the UI "looks right" if rules correctness is unverified. | `[Validated]` |
| AC-5 | Edge case | If a spec contains unresolved TBDs, evaluation reports flag those areas as provisional rather than silently passing. | `[Assumed: verify]` |

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | Golden scenarios are representative enough | Real use cases regularly fail outside the covered scenarios | Expand scenario library and revisit north-star thresholds |
| FC-2 | Rules canon and implementation stay aligned | Explanations cite rules that no longer match behavior | Add drift detection and audit workflow |
| FC-3 | Spec coverage will stay current | New features ship with no spec mapping | Block merge or require retroactive spec attachment |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| All bounded product specs | Product | In progress | This spec depends on the rest of the system |
| Test harness and fixtures | Technical | Partially present | Rails test structure exists, but product scenarios do not |

## 11. Open questions / TBDs

| ID | Question | Why it matters | Owner |
|---|---|---|---|
| TBD-1 | What measurable threshold defines "without relying heavily on the rulebook"? | Needed for UX evaluation | Product owner |
| TBD-2 | What minimum class/race/spell coverage is required for v1? | Needed for release gating | Product owner |
| TBD-3 | What format should the coverage matrix take: markdown, generated report, or both? | Affects maintenance workflow | Product owner |

## 12. Evaluation hooks

- Golden journeys for creation and level-up
- Negative legality journeys for blocked options
- Coverage matrix mapping spec IDs to tests and known gaps
- Drift audit between canon content, behavior, and explanations
