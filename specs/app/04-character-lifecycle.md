# Specification: Character Lifecycle

> **Spec type:** Workflow
> **Status:** Draft
> **Decision owner:** Product owner
> **Primary executor:** Engineer
> **Last updated:** 2026-07-22

---

## 1. Why this spec exists

The app needs a clear lifecycle for what a character is, when it is valid, when
it can be changed, and how it participates in campaigns. Without this, creation,
editing, level-up, and collaboration will conflict.

## 2. Outcome statement

**After this spec is executed:**
A character moves through explicit lifecycle states that distinguish draft creation, validated play-ready states, and later progression changes such as level-up and sharing.

**Verification method:**
Trace a character from account creation through creation, validation, level-up,
and campaign sharing without ambiguous ownership or legality rules.

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| First anchor scope is create a new character and level it up inside the app | `[Validated]` | Direct user answer |
| Import, editing, and archive/history matter but are not the anchor starting point | `[Validated]` | User likes them, but not first |
| Strict legality gates should block invalid finalized states for now | `[Validated]` | Direct user answer |

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| S-1 | Draft character creation state | User can start but not necessarily finalize immediately |
| S-2 | Validated playable state | Character meets legality requirements |
| S-3 | Level-up transition state | Character enters a guided progression workflow |
| S-4 | Shared state | Character can be visible in a campaign context |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| X-1 | Retirement/archive rules | Important later but not anchor scope |
| X-2 | Full import migration lifecycle | Needs separate spec |
| X-3 | Simultaneous co-editing lifecycle | Collaboration is initially read-focused |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| Player owner | Create, validate, and progress a character | Primary actor |
| GM viewer | See shared state of a character | Secondary actor |

## 7. Flow / state changes

Suggested lifecycle:

1. `Draft` - incomplete or not yet validated
2. `PlayableValid` - legal under chosen rules context
3. `LevelUpInProgress` - temporary workflow state
4. `PlayableValidUpdated` - newly validated post-level-up state
5. `SharedToCampaign` - visibility overlay, not necessarily a separate lifecycle root

Open modeling note:

- Sharing may be an orthogonal state rather than a lifecycle step. `[Unknown: TBD]`

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | A new character can exist in a draft state before being finalized as legally playable. | `[Assumed: verify]` |
| AC-2 | Behavioral | A character cannot enter the playable valid state unless required legality checks pass. | `[Validated]` |
| AC-3 | Behavioral | Level-up occurs as an explicit transition rather than a silent field edit. | `[Validated]` |
| AC-4 | Negative | A shared campaign view does not transfer character ownership away from the player by default. | `[Assumed: verify]` |
| AC-5 | Edge case | If a rules update invalidates an existing character, the app preserves the prior valid state and surfaces the mismatch. | `[Unknown: TBD]` |

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | Drafts and finalized states can share the same storage shape safely | Incomplete drafts are mistaken for valid characters elsewhere in the app | Add explicit state boundaries before campaign features |
| FC-2 | Level-up can be modeled as a clean transition | Users need to change unrelated fields mid-level-up | Revisit edit vs progression boundaries |
| FC-3 | Sharing is orthogonal to lifecycle | Campaign permissions mutate character validity logic | Split sharing into separate permission model |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| Domain model | Technical | In progress | `03-domain-model.md` |
| Rules canon | Content | In progress | `02-rules-canon.md` |

## 11. Open questions / TBDs

| ID | Question | Why it matters | Owner |
|---|---|---|---|
| TBD-1 | Should drafts be saveable when invalid, or only when incomplete? | Changes strictness and user recovery | Product owner |
| TBD-2 | Is sharing a lifecycle state or a separate permission overlay? | Changes data model and permissions | Product owner |
| TBD-3 | How should legacy characters behave after canon changes? | Changes revisions and evaluation | Product owner |

## 12. Evaluation hooks

- State machine tests for each legal lifecycle transition
- Regression case: invalid draft cannot masquerade as playable character
- Regression case: level-up creates an auditable transition event
