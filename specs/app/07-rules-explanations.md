# Specification: Rules Explanations

> **Spec type:** Product/feature
> **Status:** Draft
> **Decision owner:** Product owner
> **Primary executor:** Engineer plus designer
> **Last updated:** 2026-07-22

---

## 1. Why this spec exists

Strict legality only works if users trust the system. Trust requires the app to
show not just what is blocked or changed, but why, based on what rule, and in
what context.

## 2. Outcome statement

**After this spec is executed:**
Whenever the app enforces, recommends, or blocks a character decision, the user can see an explanation with the exact reason and source.

**Verification method:**
Inspect creation and level-up flows and confirm every enforced decision can be
traced to a source-backed explanation.

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| The user wants exact reason plus source, not just a short generic message | `[Validated]` | Direct user answer |
| Explanations are critical to validating the rules themselves | `[Validated]` | User wants strictness partly to verify rule correctness |

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| S-1 | Block reason explanations | Why a choice is not allowed |
| S-2 | Applied rule explanations | What happened after a legal choice |
| S-3 | Source citation display | Visible source metadata for explanations |
| S-4 | Rule-context display | Which canon/override context is active |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| X-1 | Long-form tutorial content for every rule topic | Different content problem |
| X-2 | Natural-language generative paraphrasing detached from source | Risks hallucination and loss of trust |
| X-3 | Social discussion or comments on rules | Not part of core trust loop |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| Player | Understand why the app allows or blocks something | Primary actor |
| GM | Understand shared character legality decisions | Secondary actor |
| Rules admin | Verify explanations match canon | Support role |

## 7. Flow / state changes

1. User attempts or reviews a rules-relevant action.
2. App evaluates the action against rules context.
3. App returns result plus structured explanation payload.
4. UI presents result, reason, and citation without forcing context-switching.

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | Every blocked creation or level-up action shows a specific reason tied to an identifiable rule. | `[Validated]` |
| AC-2 | Behavioral | Every explanation includes source metadata sufficient for the user to inspect the underlying rule. | `[Validated]` |
| AC-3 | Behavioral | The explanation identifies the active rules context, including when an override affects the result. | `[Unknown: TBD]` |
| AC-4 | Negative | The app does not present unexplained hard stops for legality-critical actions. | `[Validated]` |
| AC-5 | Negative | The app does not substitute a vague summary for source-backed reasoning in strict mode. | `[Validated]` |
| AC-6 | Edge case | If multiple rules jointly cause a block, the explanation preserves the primary reason and reveals supporting rules. | `[Unknown: TBD]` |

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | A single explanation can usually map to a single rule cause | Users frequently encounter compound blockers with no clear main cause | Design a multi-rule explanation pattern |
| FC-2 | Source metadata is available for all enforced rules | Some legality checks cannot cite their origin | Stop calling those checks production-ready |
| FC-3 | Strict explanations remain readable | Users are overwhelmed by explanation density and ignore them | Introduce layered explanation depth, not reduced correctness |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| Rules canon with citations | Content | In progress | `02-rules-canon.md` |
| Creation and level-up enforcement events | Technical | Unknown | Need a structured evaluation output |

## 11. Open questions / TBDs

| ID | Question | Why it matters | Owner |
|---|---|---|---|
| TBD-1 | What is the minimum citation shape the UI must expose? | Affects trust and layout | Product owner |
| TBD-2 | How should overrides be shown compared with official canon? | Critical for house-rule trust | Product owner |
| TBD-3 | Should the app distinguish between "blocked", "recommended", and "auto-applied" explanation types visually? | Affects UX design and clarity | Product owner |

## 12. Evaluation hooks

- Explanation coverage audit for every blocked choice in golden scenarios
- Citation presence test for every enforced rule
- Override scenario showing official and modified rule context distinctly
