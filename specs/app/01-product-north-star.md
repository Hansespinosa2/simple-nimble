# Specification: Product North Star

> **Spec type:** Product/feature
> **Status:** Draft
> **Decision owner:** Product owner
> **Primary executor:** Cross-functional team
> **Last updated:** 2026-07-22

---

## 1. Why this spec exists

The current repo proves some data structures and CRUD pages, but it does not yet
define what product is being built. This spec sets the product boundary, primary
user, success criteria, and non-goals so later feature specs can stay aligned.

## 2. Outcome statement

**After this spec is executed:**
A player can create and level a legal Nimble character inside the app with rules-backed guidance and without relying heavily on the rulebook.

**Verification method:**
Run golden user journeys for creation and level-up and confirm a player can complete them using the app's guidance, validations, and explanations.

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| Primary user is a player managing their own character | `[Validated]` | Direct user answer |
| Core product job is character sheet manager first, builder second, spell/rules reference third | `[Validated]` | Direct user answer |
| The single capability that must be excellent first is level-up | `[Validated]` | Direct user answer |
| The app should hard-stop invalid choices for now | `[Validated]` | User expects strictness now to verify rules correctness |
| The app should eventually become more permissive with warnings | `[Assumed: verify]` | User said likely later change |
| The product is Nimble-first, not fully system-agnostic | `[Validated]` | Direct user answer |
| The product should support house rules soon after the core release | `[Validated]` | Direct user answer |
| Shared campaign collaboration matters, but it is not the core promise | `[Validated]` | User prioritized character legality over collaboration |
| Accounts and login are required from the start of shared functionality | `[Validated]` | Direct user answer |

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| S-1 | Legal character creation | The app guides a player through a valid starting character |
| S-2 | Legal level-up | The app computes and enforces valid changes when a character levels |
| S-3 | Rules-aware explanations | The app explains why a choice is legal or illegal and cites its source |
| S-4 | Structured spell/rules reference | Rules content is stored in a curated, queryable format |
| S-5 | Shared viewing with the GM | Collaboration begins with player-owned sheets shared to a campaign context |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| X-1 | Full play-session companion with tactical combat flow | User explicitly deprioritized play-companion concerns for now |
| X-2 | Generic tabletop engine for many systems | Product is Nimble-first |
| X-3 | Open-ended freeform character editor as the primary experience | Current focus is legal guidance, not unrestricted editing |
| X-4 | Full GM-authoritative campaign manager | Collaboration matters, but not as the core value proposition |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| Player | Create, level, and manage a legal character | Primary actor |
| GM | Inspect shared player sheets and campaign-linked data | Secondary actor |
| Rules admin/content curator | Maintain structured rules canon | Required for long-term correctness |

## 7. Flow / state changes

1. Player creates an account.
2. Player creates a character or selects one they already own.
3. App guides the player through a legal state transition.
4. App explains blocked or recommended options using rules-backed reasoning.
5. Player saves a valid character state.
6. Player can later share the character into a campaign context.

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | A player can complete a legal character creation flow inside the app without manually calculating rule-derived fields outside the app. | `[Assumed: verify]` |
| AC-2 | Behavioral | A player can complete a legal level-up flow and the app only permits options valid for the chosen class, level, and rules state. | `[Validated]` |
| AC-3 | Behavioral | When the app blocks a choice, it shows the exact rule reason and a source reference. | `[Validated]` |
| AC-4 | Negative | The product does not require the player to use a separate spreadsheet or paper aid for the core creation and level-up flows. | `[Assumed: verify]` |
| AC-5 | Negative | The first release does not optimize for real-time tactical combat assistance. | `[Validated]` |
| AC-6 | Dependency | Rules content required for creation and level-up exists in structured, versioned form before those flows are considered complete. | `[Validated]` |

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | Rules can be represented accurately enough for hard-stop legality | Core flows require frequent manual overrides or out-of-band exceptions | Stop expanding UX scope; revisit rules canon and house-rule model |
| FC-2 | Players value strict legality enough to tolerate blocking flows | Users abandon the level-up flow because it feels overly rigid | Re-open permissiveness decision in this spec and the level-up spec |
| FC-3 | Collaboration can wait behind character legality | Shared use cases dominate feedback before creation/level-up is stable | Reprioritize campaign-sharing scope explicitly rather than implicitly |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| Structured rules canon | Product/content | In progress | Defined in `02-rules-canon.md` |
| User account model | Technical/product | Unknown | Not present in current schema |
| Character legality engine | Technical | Unknown | Not present in current repo |

## 11. Open questions / TBDs

| ID | Question | Why it matters | Owner |
|---|---|---|---|
| TBD-1 | How much of character editing should remain legal-only versus freeform? | Changes lifecycle, permissions, and save rules | Product owner |
| TBD-2 | What exact threshold counts as "without relying heavily on the rulebook"? | Needed for measurable UX evaluation | Product owner |
| TBD-3 | When should import of existing characters enter scope? | Changes creation and lifecycle | Product owner |

## 12. Evaluation hooks

- Golden journey: brand-new player creates a legal starting character
- Golden journey: existing legal character levels up one level
- Coverage check: every blocked choice shows a rules explanation
- Coverage check: every legal transition is represented by at least one test scenario
