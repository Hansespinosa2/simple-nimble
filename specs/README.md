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

## Spec Sync: Tracking Acceptance Criteria Implementation

Each specification document (01 through 09) contains **acceptance criteria** in section 8. These criteria define what must be true for the feature to be considered complete.

The `spec sync` system automatically tracks which acceptance criteria have been implemented, are in-progress, blocked, or still todo.

### How It Works

1. **System reads specs** from `app/[0-9][0-9]-*.md`
2. **Extracts acceptance criteria** (marked as AC-1, AC-2, etc.)
3. **Tracks implementation status** via:
   - **Manual marks** (stored in `implementation_status.yml`)
   - **Git history** (scans commit messages for criterion references)
4. **Shows unified status** via rake tasks

### Reference Format

Acceptance criteria use the format **`S-NN:AC-N`** where:
- `S-NN` = Spec number (e.g., S-05 for character creation)
- `AC-N` = Acceptance criterion number (e.g., AC-1, AC-2)

Example: `S-05:AC-1` refers to the first acceptance criterion in spec 05-character-creation.md

### Usage

#### View Implementation Status

```bash
# See all criteria across all specs
bundle exec rake spec_sync:status

# Filter to one spec
bundle exec rake "spec_sync:status[S-05]"

# Filter to one criterion
bundle exec rake "spec_sync:status[S-05:AC-1]"
```

Output shows each criterion with:
- Reference (e.g., S-05:AC-1)
- Implementation status: `todo`, `in_progress`, `blocked`, or `done`
- Criterion text
- Spec confidence level from the spec document
- Manual status (if set)
- Linked commits (if found in git history)

#### Mark a Criterion

```bash
# Mark as in-progress with notes
bundle exec rake "spec_sync:mark[S-05:AC-1,in_progress,Building form validation]"

# Mark as blocked with reason
bundle exec rake "spec_sync:mark[S-06:AC-2,blocked,Waiting for character lifecycle model]"

# Clear manual mark (reverts to based on git history)
bundle exec rake "spec_sync:mark[S-05:AC-1,todo]"
```

#### Validate Configuration

```bash
bundle exec rake spec_sync:validate
```

### Implementation Status

Each criterion has a status computed from:

1. **Manual override** (if you explicitly marked it)
   - `in_progress` — work is actively happening
   - `blocked` — cannot proceed without something else

2. **Git history** (if any commit mentions the criterion)
   - Commit message: `"feat: Add validation for S-05:AC-1"`
   - System finds the reference → marks criterion as `done`

3. **Default** (if neither above apply)
   - `todo` — not yet started

Priority: Manual overrides take precedence over git history, which takes precedence over the default.

### Workflow Example

```bash
# Day 1: Start working on character creation acceptance criteria
$ bundle exec rake "spec_sync:mark[S-05:AC-1,in_progress,Designing form]"
$ bundle exec rake "spec_sync:mark[S-05:AC-2,in_progress,Implementing validation]"

# View progress
$ bundle exec rake spec_sync:status[S-05]

# Day 2: Hit a blocker
$ bundle exec rake "spec_sync:mark[S-05:AC-1,blocked,Waiting for schema design]"

# Day 3: Complete and commit work
$ git commit -m "feat: Add character creation form

- Implement form layout per S-05:AC-1
- Add field validation per S-05:AC-2
- Calculate derived attributes per S-05:AC-3"

# System now shows criteria as [done] automatically
$ bundle exec rake spec_sync:status[S-05]
S-05:AC-1 [done] ... (auto-detected from commit)
S-05:AC-2 [done] ... (auto-detected from commit)
S-05:AC-3 [done] ... (auto-detected from commit)
```

### Files

- `implementation_status.yml` — Manual status overrides (sparse YAML)
- `app/[0-9][0-9]-*.md` — Product specifications with acceptance criteria
- `lib/spec_sync/` — System code (parsers, trackers, indexers)
- `lib/tasks/spec_sync.rake` — Rake task definitions

### Key Design Principles

- **Git is the source of truth** — Mention criteria in commits; no separate "done" marking needed
- **Manual marks are for work-in-progress** — Use `in_progress` and `blocked` to track active work
- **No "done" manual status** — Done comes only from git history
- **Sparse storage** — YAML only stores exceptions (not-todo statuses)
- **Always fresh** — Status is computed on-demand, never stale

### For Developers

When you complete work on a criterion, mention it in your commit message:

```bash
git commit -m "feat: Implement character creation validation

- Add form validations per S-05:AC-1
- Prevent invalid combinations per S-05:AC-2
- Handle edge cases per S-05:AC-5

Closes #42"
```

The system will automatically scan the commit message, find `S-05:AC-1`, `S-05:AC-2`, and `S-05:AC-5`, and link them to that commit. When you run `rake spec_sync:status`, those criteria will show as `[done]` with the commit linked.

### Documentation

For detailed information, see the session workspace documents:
- **Quick Reference** — How to use the system with practical examples
- **Architecture** — Deep dive into how the system works
- **Bug Fixes** — What was fixed and why (includes before/after code)
