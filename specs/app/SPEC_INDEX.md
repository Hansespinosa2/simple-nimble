# Specification Index

> **System purpose:** define a linked set of documents that acts as product context,
> implementation success criteria, and evaluation input for `simple-nimble`.
> **Current status:** draft set established from repo analysis plus product discovery on 2026-07-22.

---

## Product summary

`simple-nimble` is evolving from a Rails CRUD prototype into a **Nimble-first,
rules-aware character product**.

The core product promise is:

> A player can create and level a legal character inside the app without needing
> to consult the rulebook much, while receiving rule-grounded explanations for
> what is allowed and why.

## What the current repo already shows

- Character CRUD exists today. `[Validated - repo state]`
- A character currently stores summary fields plus nested `StatSet`, `SkillSet`,
  and `TraitSet`. `[Validated - schema.rb]`
- Spells exist as a reference table and can be linked to characters. `[Validated - schema.rb]`
- The current UI is generic CRUD, not rules-aware creation or level-up. `[Validated - app/views/characters/*]`
- There is no user/account model yet, even though the intended product now
  requires login and collaboration. `[Validated - schema.rb][Open gap]`

## Spec graph

| ID | Document | Why it exists | Primary dependency | Execution priority |
|---|---|---|---|---|
| S-00 | `SPEC_TEMPLATE.md` | Gives a repeatable format for new bounded specs | None | Immediate |
| S-01 | `01-product-north-star.md` | Defines product purpose, audience, and success criteria | Discovery inputs | 1 |
| S-02 | `02-rules-canon.md` | Defines how rules become structured, versioned truth | S-01 | 2 |
| S-03 | `03-domain-model.md` | Defines entities, relationships, and ownership model | S-01, S-02 | 3 |
| S-04 | `04-character-lifecycle.md` | Defines the end-to-end character state machine | S-01, S-03 | 4 |
| S-05 | `05-character-creation.md` | Defines new-character flow and validation | S-02, S-03, S-04 | 5 |
| S-06 | `06-level-up.md` | Defines the anchor workflow and legality checks | S-02, S-03, S-04 | 6 |
| S-07 | `07-rules-explanations.md` | Defines explanation UX and citation expectations | S-02, S-05, S-06 | 7 |
| S-08 | `08-campaign-sharing.md` | Defines accounts, campaigns, roles, and sharing | S-01, S-03, S-04 | 8 |
| S-09 | `09-evaluation-and-coverage.md` | Defines evaluation, golden scenarios, and spec coverage | All prior specs | 9 |

## Recommended authoring order

1. Lock the product north star.
2. Lock the rules canon and content-authoring model.
3. Lock the domain model.
4. Lock the character lifecycle.
5. Lock creation and level-up.
6. Lock explanations and campaign sharing.
7. Use the evaluation spec to test whether the rest are complete.

## Major open decisions worth user attention

These are worth direct product attention because they change multiple downstream specs.

| Decision | Why it matters | Current status |
|---|---|---|
| Exact first-release scope between creation, editing, import, and level-up | Changes lifecycle, permissions, and evaluation scope | `[Assumed: v1 anchor is create + level-up]` |
| House-rule model depth | Changes rules canon, domain model, and explanation system | `[Unknown: TBD]` |
| GM edit permissions | Changes sharing, ownership, audit history, and conflict rules | `[Unknown: TBD]` |
| Import strategy for existing characters | Changes creation and lifecycle significantly | `[Unknown: TBD]` |

## Definition of success for the spec system

The spec system is working when:

1. A future feature can be attached to one primary spec without ambiguity.
2. Rules correctness can be evaluated from structured cases, not memory.
3. Implementation tasks can cite specific spec IDs and acceptance criteria.
4. Missing product decisions show up as explicit TBDs instead of hidden assumptions.
