# Specifications

This directory contains the product and system specifications for `simple-nimble`.

The repo currently contains a thin Rails CRUD prototype for characters and spells.
These specs define the intended product beyond that prototype so the codebase can
be evolved deliberately instead of by ad hoc feature work.

## Directory structure

- `application/` Product-level specifications, roadmap order, and reusable spec template
- `controllers/` Controller-level behavior specs as implementation gets formalized
- `models/` Domain and data-model specifications, including diagrams
- `views/` UI and interaction specifications

## Product spec set

Start with these files in `application/`:

1. `SPEC_INDEX.md` - map of the full specification system
2. `SPEC_TEMPLATE.md` - reusable template for new bounded specs
3. `01-product-north-star.md` - product purpose, users, principles, and success criteria
4. `02-rules-canon.md` - source-of-truth rules content and versioning model
5. `03-domain-model.md` - product entities and relationships
6. `04-character-lifecycle.md` - end-to-end lifecycle for a character
7. `05-character-creation.md` - creation flow and validation rules
8. `06-level-up.md` - level-up flow, legality enforcement, and recalculation rules
9. `07-rules-explanations.md` - how the app explains legal and illegal states
10. `08-campaign-sharing.md` - player/GM/campaign collaboration model
11. `09-evaluation-and-coverage.md` - acceptance, evaluation, and coverage model

## Current status

- The documents above are draftable now with a mix of known decisions and explicit TBDs.
- Any unresolved decision that blocks implementation is marked as `[Unknown: TBD]`.
- These specs should be updated as decisions are validated, not treated as frozen prose.
