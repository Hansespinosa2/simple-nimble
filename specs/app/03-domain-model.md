# Specification: Domain Model

> **Spec type:** Domain/data
> **Status:** Draft
> **Decision owner:** Product owner
> **Primary executor:** Engineer
> **Last updated:** 2026-07-22

---

## 1. Why this spec exists

The current schema stores a single character shape, but the intended product now
requires accounts, ownership, collaboration, rules versioning, and auditable
state transitions. This spec defines the product entities before the app grows
further.

## 2. Outcome statement

**After this spec is executed:**
The product has a domain model that can represent players, accounts, characters, rules contexts, campaigns, sharing roles, and legality-driven character state transitions.

**Verification method:**
Each primary workflow in the lifecycle, creation, level-up, and campaign-sharing
specs can be expressed without inventing hidden entities.

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| Accounts and login are required from the start of shared functionality | `[Validated]` | Direct user answer |
| Player-owned characters are primary | `[Validated]` | Direct user answer |
| GM read access is the first collaboration behavior | `[Validated]` | User prioritized read-only sharing first |
| GM edit access may matter later | `[Assumed: verify]` | User liked it, but did not promote it to first priority |
| Characters maintain full revision history at every lifecycle stage | `[Validated]` | Direct user answer — enables health/inventory tracking over time |
| Revision strategy: full snapshots at lifecycle milestones + deltas within states | `[Validated]` | Direct user answer |
| A character can belong to multiple campaigns simultaneously | `[Validated]` | Direct user answer |
| Sharing is a permission overlay, not a lifecycle state | `[Validated]` | Direct user answer |
| House rules are out of scope for v1 | `[Validated]` | Direct user answer |

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| S-1 | Account and identity entities | Required for ownership and sharing |
| S-2 | Character ownership and state | Character belongs to an account and may exist in multiple workflow states |
| S-3 | Rules context entity | Character legality should depend on canon plus optional overrides |
| S-4 | Campaign and membership entities | Needed for sharing and GM visibility |
| S-5 | Revision/audit shape | Needed for strict legality and later overrides |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| X-1 | Tactical encounter entities | Deprioritized play-companion scope |
| X-2 | Marketplace, publishing, or social feed entities | Not part of core promise |
| X-3 | Fully generic multi-system abstraction | Would dilute Nimble-first modeling |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| Account holder | Own characters and collaborate in campaigns | Primary owner |
| GM | View linked characters and campaign context | Secondary actor |
| Rules admin | Publish canon and overrides | Product support role |

## 7. Flow / state changes

Suggested entity set:

1. `Account`
2. `Character`
3. `CharacterRevision`
4. `RulesetVersion`
5. `RulesOverride`
6. `Campaign`
7. `CampaignMembership`
8. `CharacterShare` or equivalent join model
9. Rule content entities such as `Class`, `Race`, `Spell`, `Feature`, `Prerequisite`, `ProgressionRule`

Current repo entities that likely remain but need reframing:

- `Character`
- `Spell`
- `CharacterSpell`
- `StatSet`
- `SkillSet`
- `TraitSet`

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | The model can represent which account owns a character and which campaign members can view it. | `[Assumed: verify]` |
| AC-2 | Behavioral | The model can represent a character's rules context separately from the character's mutable fields. | `[Assumed: verify]` |
| AC-3 | Behavioral | The model can preserve prior character states or revisions relevant to legality and audit. | `[Validated]` |
| AC-4 | Negative | Campaign membership is not used as a substitute for account ownership. | `[Assumed: verify]` |
| AC-5 | Dependency | Creation, level-up, and sharing specs must not introduce entities that are absent from this spec. | `[Validated]` |

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | The current nested set structure can scale to product needs | Repeated workflow logic bypasses the model layer entirely | Revisit entity boundaries before more CRUD growth |
| FC-2 | A simple share model is enough for v1 collaboration | Permissions become ambiguous between owner, player, and GM | Stop and define explicit role/capability matrix |
| FC-3 | Revision history can be added later with little cost | Legal transitions become impossible to audit after mutations | Prioritize revision model before advanced editing |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| Rules canon spec | Product/content | In progress | `02-rules-canon.md` |
| Identity/auth product decision | Product | Validated | Accounts required |
| Collaboration scope | Product | Partially known | Read-only GM access first |

## 11. Open questions / TBDs

All TBDs resolved. No open questions remain for this spec.

## 12. Evaluation hooks

- Entity audit: each top-level workflow names only entities defined here
- Permission matrix coverage for player owner vs GM viewer
- Migration audit from current schema to target model
