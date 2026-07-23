# Specification: Rules Canon

> **Spec type:** Domain/data
> **Status:** Draft
> **Decision owner:** Product owner
> **Primary executor:** Engineer plus rules/content curator
> **Last updated:** 2026-07-22

---

## 1. Why this spec exists

The product cannot enforce legality or explain rules unless Nimble's rules exist
as structured, versioned application data. This spec defines what "source of
truth" means for rules content.

## 2. Outcome statement

**After this spec is executed:**
The app has a curated, versioned, structured in-app rules database that can drive character legality, recommendations, and rule explanations.

**Verification method:**
Check that creation and level-up decisions can be answered from structured rules
records rather than hard-coded UI logic or freeform text blobs alone.

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| Rules truth should live in a structured in-app rules database | `[Validated]` | Direct user answer |
| Rules should be curated and versioned | `[Validated]` | Implied by structured source-of-truth decision |
| Nimble is the canonical system first | `[Validated]` | Direct user answer |
| House rules should be supported soon | `[Validated]` | Direct user answer |
| Rules explanations should cite exact reason and source | `[Validated]` | Direct user answer |
| Source citations use section references (e.g., Chapter 3, Section 5) | `[Validated]` | Direct user answer |
| Overrides are stored alongside — not replacing — the original canon rule | `[Validated]` | Direct user answer |
| House rules are out of scope for v1 | `[Validated]` | Direct user answer |

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| S-1 | Canonical rules entities | Classes, races, spells, progression tables, prerequisites, derived formulas |
| S-2 | Rules versioning | The app can identify which ruleset version a character depends on |
| S-3 | Citation metadata | Every enforceable rule can point to its source |
| S-4 | Override model | The system can represent official rule plus approved override paths |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| X-1 | Unstructured prose-only rules import as the long-term model | Prevents legality engine and explanations |
| X-2 | Multi-system rules engine | Product is Nimble-first |
| X-3 | Community-authored open marketplace of rules packs | Too broad for current product phase |
| X-4 | House rules | Out of scope for v1; to be introduced in a later release |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| Rules admin | Publish correct structured rule content | New role implied by product |
| Player | Consume rules indirectly through flows and explanations | Should not have to manage canon directly |
| GM | May later apply campaign-level overrides | Likely future role |

## 7. Flow / state changes

1. Rules source is entered or imported into structured storage.
2. Rules are normalized into entities plus relationships.
3. Each rule element receives source metadata and versioning.
4. Characters reference a specific rules context.
5. Overrides, if present, are stored distinctly from core canon.

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | Any rule required to determine character legality can be queried as structured data, not only read as prose. | `[Assumed: verify]` |
| AC-2 | Behavioral | Each enforceable rule element includes a source reference that can be surfaced in UI explanations. | `[Validated]` |
| AC-3 | Behavioral | A character can be associated with a specific rules version or rules context. | `[Assumed: verify]` |
| AC-4 | Negative | The app does not rely on scattered hard-coded conditionals as the only implementation of game rules. | `[Assumed: verify]` |
| AC-5 | Edge case | If an override conflicts with base canon, the system preserves both the official rule and the active override record. | `[Validated]` |
| AC-6 | Dependency | Creation and level-up specs cannot be finalized until the minimum required rules entities are enumerated. | `[Validated]` |

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | Nimble rules are structured enough for machine evaluation | Key legality checks still depend on human interpretation each time | Stop on new flow work and define missing rule shapes |
| FC-2 | Versioning can remain lightweight | Rule updates break existing characters silently | Add migration and compatibility policy before shipping |
| FC-3 | House rules can fit on top of canon cleanly | Overrides require destructive mutation of base rules | Re-open override model before campaign features proceed |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| Full Nimble rules corpus access | Content | Unknown | Not represented in repo yet |
| Data model for rules entities | Technical | Unknown | See `03-domain-model.md` |
| Editorial process for corrections | Process | Unknown | No owner formalized yet |

## 11. Open questions / TBDs

| ID | Question | Why it matters | Owner |
|---|---|---|---|
| TBD-1 | What exact rule entities are required for v1 legality? | Prevents over- or under-modeling the canon — awaiting Nimble PDF source documents | Product owner |

TBD-2 and TBD-3 resolved. House rules are out of scope for v1. Citations use section references.

## 12. Evaluation hooks

- Rule coverage matrix: every level-up decision cites one or more canonical rules
- Schema coverage: every creation field maps to a structured rule or explicit freeform field
- Regression test: updating a rule version does not silently change prior character legality
