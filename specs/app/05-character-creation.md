# Specification: Character Creation

> **Spec type:** Product/feature
> **Status:** Draft
> **Decision owner:** Product owner
> **Primary executor:** Engineer
> **Last updated:** 2026-07-22

---

## 1. Why this spec exists

The current app can create a record with fields, but it cannot guide a player
through a rules-aware creation process. This spec defines the bounded creation
experience.

## 2. Outcome statement

**After this spec is executed:**
A player can create a new character through a guided flow that produces a legal starting character under a chosen Nimble rules context.

**Verification method:**
Run a full starting-character journey and confirm the app prevents illegal
choices, calculates required values, and produces a playable valid character.

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| Character creation is part of the first anchor scope | `[Validated]` | Direct user answer |
| The app should guide and enforce legal choices | `[Validated]` | Direct user answer |
| Rules explanations should include exact reason and source | `[Validated]` | Direct user answer |

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| S-1 | New character start flow | Enter or select required starting decisions |
| S-2 | Rules-aware validation | Prevent illegal combinations and missing required choices |
| S-3 | Derived values calculation | Stats, traits, spells, and related values are not all manual |
| S-4 | Draft save and resume behavior | Important for realistic usage, though exact boundaries are TBD |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| X-1 | Importing an existing paper or external-sheet character | Needs a separate spec |
| X-2 | Freeform unrestricted creation mode as the default | Conflicts with strict legality goal |
| X-3 | Full campaign onboarding during creation | Collaboration is not the primary creation outcome |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| Player | Produce a legal starting character with confidence | Primary actor |

## 7. Flow / state changes

Suggested creation flow:

1. Create draft
2. Choose rules context
3. Choose or enter required identity/background fields
4. Choose race/class/starting options
5. Allocate or derive stats and traits
6. Choose starting spells/features where relevant
7. Resolve validation errors and finalize

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | The creation flow collects all fields required for a legal starting character and prevents finalization until they are valid. | `[Assumed: verify]` |
| AC-2 | Behavioral | When a player selects a starting option with downstream effects, the app recalculates all directly affected derived values before finalization. | `[Assumed: verify]` |
| AC-3 | Behavioral | A player can see why an option is unavailable or invalid from inside the creation flow. | `[Validated]` |
| AC-4 | Negative | The creation flow does not ask the player to manually perform core legality calculations outside the app. | `[Assumed: verify]` |
| AC-5 | Edge case | If a player leaves the flow before finalization, the draft can be resumed without losing prior legal choices. | `[Unknown: TBD]` |
| AC-6 | Dependency | Starting-option rules for the relevant classes/races/spells must exist in structured canon before the flow is called complete. | `[Validated]` |

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | Creation legality is fully modelable from structured data | The UI needs special-case logic for many starting paths | Re-open canon coverage before extending UI |
| FC-2 | Draft resume can be added without affecting legality | Partial saves routinely create impossible recovery states | Define draft validation boundaries explicitly |
| FC-3 | One creation flow can handle all starting archetypes | Certain classes require unique subflows that break the general model | Split specialized creation specs if needed |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| Rules canon coverage for starting rules | Content | Unknown | Not yet enumerated |
| Character lifecycle draft/final states | Product | In progress | `04-character-lifecycle.md` |

## 11. Open questions / TBDs

| ID | Question | Why it matters | Owner |
|---|---|---|---|
| TBD-1 | What exact creation steps are mandatory versus optional? | Needed for flow design and validation | Product owner |
| TBD-2 | What kind of draft-saving behavior is acceptable before legality is achieved? | Changes persistence and UX | Product owner |
| TBD-3 | Should the flow recommend builds or only validate them? | Changes assistant behavior and explanation UX | Product owner |

## 12. Evaluation hooks

- Golden scenarios: one legal starting character per starter class in v1 scope
- Negative scenarios: illegal starting combinations are blocked with source-backed explanations
- Resume scenario: user leaves mid-creation and returns to the same draft
