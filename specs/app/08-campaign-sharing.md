# Specification: Campaign Sharing

> **Spec type:** Collaboration
> **Status:** Draft
> **Decision owner:** Product owner
> **Primary executor:** Engineer
> **Last updated:** 2026-07-22

---

## 1. Why this spec exists

The product is not only a solo character tool. It needs a campaign context where
players and GMs can interact around sheets, but without losing the player-owned
character model that anchors the product.

## 2. Outcome statement

**After this spec is executed:**
An account-owning player can share a character into a campaign so the GM can inspect it, while ownership and permissions remain explicit.

**Verification method:**
Create player and GM accounts, share a character into a campaign, and confirm the
GM can view what is allowed without taking ownership or making unauthorized changes.

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| Shared app with party/campaign collaboration matches the next meaningful version | `[Validated]` | Direct user answer |
| Most important collaboration behavior is players sharing read-only sheets with the GM | `[Validated]` | Direct user answer |
| GM edit ability is interesting but secondary | `[Assumed: verify]` | User liked it, but not as the first collaboration behavior |
| Accounts and login are required | `[Validated]` | Direct user answer |

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| S-1 | Accounts and login | Required foundation |
| S-2 | Campaign container | Place where players and GM relate |
| S-3 | Read-only character sharing to GM | First collaboration target |
| S-4 | Shared campaign workspace | Important later within collaboration, but still in this doc's boundary |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| X-1 | Multi-user simultaneous editing of the same character | More complex than first collaboration target |
| X-2 | GM ownership takeover of player sheets by default | Conflicts with player-owned model |
| X-3 | Real-time tactical session synchronization | Different product phase |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| Player | Share character into campaign while staying owner | Primary actor |
| GM | Inspect player sheets and campaign context | Secondary actor |
| Campaign member | Participate in shared campaign workspace | Future-important actor |

## 7. Flow / state changes

1. User creates an account and joins or creates a campaign.
2. Player links one or more owned characters to the campaign.
3. GM gains read access according to campaign membership and permissions.
4. Shared campaign resources exist separately from character ownership.

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | A player account can share a character to a campaign without transferring character ownership. | `[Validated]` |
| AC-2 | Behavioral | A GM account can inspect shared player-linked sheets in a campaign context. | `[Validated]` |
| AC-3 | Behavioral | Accounts and permissions are required for campaign access. | `[Validated]` |
| AC-4 | Negative | A GM cannot edit a player-owned sheet unless the permission model explicitly grants that capability. | `[Assumed: verify]` |
| AC-5 | Edge case | If a player leaves a campaign, the system defines whether the shared link is removed, frozen, or transferred. | `[Unknown: TBD]` |
| AC-6 | Dependency | Campaign sharing depends on an explicit account and role model in the domain spec. | `[Validated]` |

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | Read-only sharing is enough for early collaboration | GMs immediately need editing to run their workflow | Decide explicitly whether to expand scope or defer |
| FC-2 | Campaign workspace can stay lightweight at first | Shared notes/resources become central before sheet sharing is stable | Split workspace into its own higher-priority spec |
| FC-3 | Account model is straightforward | Auth and permissions become the biggest technical blocker | Isolate auth foundation work before more collaboration features |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| Account/auth foundation | Technical | Unknown | Not present in current repo |
| Domain model for campaigns and memberships | Technical | In progress | `03-domain-model.md` |

## 11. Open questions / TBDs

| ID | Question | Why it matters | Owner |
|---|---|---|---|
| TBD-1 | What exact permissions does a GM have on a shared character in v1? | Core collaboration boundary | Product owner |
| TBD-2 | What belongs in the shared campaign workspace besides character visibility? | Changes scope significantly | Product owner |
| TBD-3 | Can one character belong to multiple campaigns? | Changes permissions and ownership handling | Product owner |

## 12. Evaluation hooks

- Player/GM permission matrix tests
- Share/unshare campaign scenarios
- Ownership invariant test: sharing never changes owner by accident
