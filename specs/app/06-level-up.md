# Specification: Level-Up

> **Spec type:** Product/feature
> **Status:** Draft
> **Decision owner:** Product owner
> **Primary executor:** Engineer
> **Last updated:** 2026-07-22

---

## 1. Why this spec exists

Level-up is the first capability the product must do exceptionally well. This
spec defines the single most important workflow in the product.

## 2. Outcome statement

**After this spec is executed:**
A player can level up a legal character inside the app and the app enforces, recalculates, and explains every required rules consequence for that level transition.

**Verification method:**
Take known valid characters through golden level-up scenarios and confirm the app
accepts only legal choices, applies rule-driven updates, and surfaces source-backed explanations.

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| Level-up is the first must-win product moment | `[Validated]` | Direct user answer |
| The app should hard-stop invalid choices for now | `[Validated]` | Direct user answer |
| The app should later likely support warnings-only flexibility | `[Assumed: verify]` | Future mode, not v1 |
| Explanations should show exact reason and source | `[Validated]` | Direct user answer |

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| S-1 | Start a level-up from an existing legal character | Entry condition |
| S-2 | Present only legal choices for that transition | Core enforcement behavior |
| S-3 | Recalculate affected values | Stats, traits, spells, class progression, and derived changes |
| S-4 | Finalize and persist the new valid character state | Exit condition |
| S-5 | Explain blocked and applied rule outcomes | Required for trust and debugging |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| X-1 | Fully freeform level editing as default behavior | Conflicts with strict v1 legality |
| X-2 | Multi-level bulk advancement in one opaque jump | Hides rules reasoning and complicates evaluation |
| X-3 | Tactical play updates unrelated to level progression | Not the anchor problem |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| Player | Advance a character correctly and confidently | Primary actor |

## 7. Flow / state changes

1. Player selects a valid character.
2. App verifies the character is eligible to level up under current rules context.
3. App enters level-up workflow.
4. App presents required and optional decisions in dependency order.
5. App recalculates affected values after each committed choice or at clearly defined checkpoints.
6. App blocks invalid outcomes and explains why.
7. App finalizes the new legal state and records the transition.

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | A player can start level-up only from a character state that the app currently marks as legally playable. | `[Assumed: verify]` |
| AC-2 | Behavioral | During level-up, the app only allows choices that are legal for the character's class, current level, selected rules context, and already-made selections in that transition. | `[Validated]` |
| AC-3 | Behavioral | On finalization, every derived field affected by the level transition is recalculated and persisted consistently. | `[Assumed: verify]` |
| AC-4 | Behavioral | For every blocked or required choice, the app shows the rule reason and source reference without requiring the user to leave the flow. | `[Validated]` |
| AC-5 | Negative | The app does not allow a player to finalize a level-up into an illegal character state. | `[Validated]` |
| AC-6 | Negative | The app does not silently mutate unrelated character data during level-up. | `[Assumed: verify]` |
| AC-7 | Edge case | If the rules context changed since the character's last valid state, the app surfaces that mismatch before or during level-up. | `[Unknown: TBD]` |
| AC-8 | Dependency | Golden level-up scenarios for each in-scope class must exist and pass before the feature is considered complete. | `[Validated]` |

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | Level-up legality can be represented deterministically | Repeated ambiguities require manual interpretation during the flow | Stop and deepen rules canon before adding polish |
| FC-2 | Derived-value recalculation boundaries are known | Bugs show partially updated sheets after level-up | Define dependency graph for recalculations before shipping |
| FC-3 | Strict hard-stop UX is acceptable for v1 | Users cannot recover from blocked choices without frustration | Re-open permissive draft behavior while preserving legality checks |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| Rules canon for progression | Content | Unknown | Must enumerate class progression rules |
| Character lifecycle transition model | Product | In progress | `04-character-lifecycle.md` |
| Explanation system | Product/UX | In progress | `07-rules-explanations.md` |

## 11. Open questions / TBDs

| ID | Question | Why it matters | Owner |
|---|---|---|---|
| TBD-1 | Should recalculations appear live after each choice or at step boundaries? | Affects UX and implementation complexity | Product owner |
| TBD-2 | Should users be allowed to enter a tentative invalid level-up draft before finalization? | Affects strictness, recovery, and persistence | Product owner |
| TBD-3 | What audit trail is required for a completed level-up? | Affects revisions, debugging, and trust | Product owner |

## 12. Evaluation hooks

- Golden scenarios for each in-scope class and archetype
- Negative scenarios for blocked illegal choices
- Regression suite ensuring no unrelated fields mutate on level-up
- Canon mismatch scenario for characters whose rules context changed
