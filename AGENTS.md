# Copilot Agent Instructions for simple-nimble

## Overview

This project uses a **spec sync system** to track which acceptance criteria from product specifications have been implemented. As you work, help developers connect their code to the specifications it implements.

## Key Concepts

### Specification and Acceptance Criteria

- **Specs:** Product specifications in `specs/app/[0-9][0-9]-*.md`
- **Acceptance Criteria:** Requirements within each spec that define completion
- **Reference format:** `S-NN:AC-N` (e.g., `S-05:AC-1`)
  - `S-05` = Specification 05 (Character Creation)
  - `AC-1` = First Acceptance Criterion in that spec

### How Spec Sync Tracks Implementation

The system uses two signals:

1. **Git history:** Commits that mention `S-NN:AC-N` are auto-detected as implementing that criterion
2. **Manual marks:** Developers can explicitly mark criteria as `in_progress` or `blocked`

## When Writing Code

### 1. Understand the Spec

When working on a feature, check what specs it relates to:

```bash
bundle exec rake spec_sync:status[S-05]
```

This shows all acceptance criteria for that spec and their implementation status.

### 2. Write Spec-Aware Commits

When your code implements an acceptance criterion, mention it in the commit message:

```bash
git commit -m "feat: Add character creation form

- Build form component per S-05:AC-1
- Implement validation logic per S-05:AC-2
- Calculate derived attributes per S-05:AC-3

Closes #42"
```

Format: Include `S-NN:AC-N` anywhere in the commit subject or body.

**Why this matters:**
- Traces code back to product requirements
- Auto-marks criteria as done in spec sync
- Makes review and debugging easier
- Maintains spec-to-code alignment

### 3. Mark Work in Progress

Before starting work, mark criteria as `in_progress`:

```bash
bundle exec rake "spec_sync:mark[S-05:AC-1,in_progress,Building form component]"
```

This tells other developers you're working on it.

### 4. Handle Blockers

If you're blocked waiting on something, mark it:

```bash
bundle exec rake "spec_sync:mark[S-06:AC-2,blocked,Waiting for character lifecycle model (S-04)]"
```

## Helpful Commands

```bash
# View all criteria for a spec
bundle exec rake spec_sync:status[S-05]

# View one criterion
bundle exec rake "spec_sync:status[S-05:AC-1]"

# View all criteria across all specs
bundle exec rake spec_sync:status

# Mark a criterion
bundle exec rake "spec_sync:mark[S-05:AC-1,in_progress,Building form]"

# Clear a manual mark
bundle exec rake "spec_sync:mark[S-05:AC-1,todo]"

# Validate spec sync config
bundle exec rake spec_sync:validate
```

## When Helping with Code

### Before Writing Code
- Ask: "Which acceptance criteria does this implement?"
- Suggest: Run `rake spec_sync:status[S-XX]` to see requirements
- Encourage: Reading the relevant spec document first

### While Writing Code
- Suggest: Breaking work into acceptance-criteria-sized chunks
- Encourage: Writing code that satisfies one criterion at a time
- Remind: Mention criteria in commit messages

### In Code Review
- Check: Do commits mention the specs they implement?
- Suggest: Adding missing `S-NN:AC-N` references
- Validate: Does the code actually satisfy the mentioned criteria?

### Example Guidance

When a developer asks to implement "character validation":

```
Good approach:
1. Read spec 05-character-creation.md section 8 (Acceptance Criteria)
2. Identify relevant criteria (e.g., S-05:AC-1, S-05:AC-2, S-05:AC-4)
3. Mark them as in_progress
4. Build form validation
5. Commit with: "feat: Add character form validation per S-05:AC-1 and S-05:AC-2"
6. Run rake spec_sync:status[S-05] to verify they're linked
```

## Spec Sync System Files

- `lib/spec_sync/` - System code (parsers, trackers, indexers)
- `lib/tasks/spec_sync.rake` - Rake task definitions
- `specs/app/[0-9][0-9]-*.md` - Product specifications
- `specs/implementation_status.yml` - Manual status overrides
- `.github/workflows/spec-sync-validate.yml` - CI validation

## Key Design Principles

1. **Git is the source of truth** — Mention criteria in commits
2. **Specs drive implementation** — Code should satisfy acceptance criteria
3. **Manual marks track active work** — Use `in_progress`/`blocked` for WIP
4. **No "done" manual status** — Done comes only from git commits
5. **Always fresh data** — Status computed on-demand from current state

## References

- Spec template: `specs/app/SPEC_TEMPLATE.md`
- Spec index: `specs/app/SPEC_INDEX.md`
- Implementation tracking: `specs/README.md` (Spec Sync section)
- Full documentation: See session workspace documents (architecture, bugs, quick reference)

---

**TL;DR:** When implementing a feature, check the relevant spec, mark criteria as you work, mention them in commits, and the system automatically tracks progress. Done!
