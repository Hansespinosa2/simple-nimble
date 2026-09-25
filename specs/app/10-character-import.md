# Specification: Character Import

> **Spec type:** Product/feature
> **Status:** Ready for implementation
> **Decision owner:** Product owner
> **Primary executor:** Engineer
> **Last updated:** 2026-09-25

---

## 1. Why this spec exists

Players need to bring existing Nimble characters into the app without manually
rebuilding them. Import must preserve the app's strict rules model: it cannot
trust derived values or let a supplied current-level sheet skip the progression
checks used by ordinary character creation and level-up.

## 2. Outcome statement

**After this spec is executed:**
A player can upload a guided, versioned JSON or CSV character file, receive
source-backed validation feedback, and save a valid character as an owned draft.

**Verification method:**
Exercise JSON and CSV imports from level 1 through higher levels; verify each
level-up is replayed by the normal planner, invalid or incomplete files leave no
character behind, and successful imports remain drafts.

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| Supported file formats are structured JSON and CSV | `[Validated]` | Guided interchange contract; no inferred PDF/image/spreadsheet parsing |
| Successful imports are saved as drafts | `[Validated]` | Import never finalizes directly to playable |
| Levels 2–20 require every sequential level-up input | `[Validated]` | No reconstruction or trust of current totals without full history |
| Current Nimble v2.0.1 catalog is authoritative | `[Validated]` | Names and choices must map to this catalog |
| Import cannot grant a story-based subclass | `[Validated]` | That still requires the GM-approved, story-noted S-08 flow |
| Import uses existing domain entities | `[Validated]` | `Character`, `LevelUp`, and `CharacterRevision`; no import-job entity |

### Interchange shape

Both formats use the same version 1 fields: `format`, `format_version`,
`character`, `rules`, `stats`, `skills`, `traits`, `spells`, `inventory_items`,
`level_ups`, and (for levels above 1) `creation`. JSON stores these as top-level
values. CSV has one character per file, the same ordered header, and one data
row; `format` and `format_version` are plain cells while each other cell is a
JSON-encoded value (`creation` may be blank for a level-1 character). Export-only
fields such as `progression`, `status_label`, and `url` are informational and
never override imported rules state.

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| S-1 | Guided upload and contract | Downloadable JSON/CSV templates; explicit format/version; bounded file size |
| S-2 | Canonical identity mapping | Resolve exact class, ancestry, background, spell, and rules names |
| S-3 | Level-1 validation | Reuse creation legality and derived-value calculations |
| S-4 | Historical progression replay | Require one finalized transition for every level from 2 through the declared current level; replay through `LevelUpPlanner` and `LevelUpService` |
| S-5 | Safe draft persistence | Associate with the importing account when present; never trust incoming owner, IDs, status, or derived maxima |
| S-6 | Tracker and inventory restoration | Restore only supported current values after canonical maxima, inventory metadata, and slots are recomputed |
| S-7 | Export-compatible interchange | JSON export includes its format version, creation baseline, current sheet, inventory, and every level-up input needed for replay |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| X-1 | PDF, image, XLSX, arbitrary third-party exports | Requires format-specific parsing and mapping that cannot be safely inferred |
| X-2 | Importing a higher-level sheet without full history | Would certify unverifiable stats, skills, or feature choices |
| X-3 | Direct import approval of story-based subclass changes | GM authority and audit trail remain in S-08 |
| X-4 | House-rule import or ruleset conversion | House rules and cross-version migration are separate canon decisions |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| Player / account holder | Import an owned character and review it before play | Imported state is always a draft |
| Anonymous local user | Import a local character where the app permits unowned characters | Must not set an account ID from the file |
| GM | Continue to approve story-based subclass changes | Import grants no GM authority |

## 7. Flow / state changes

1. Player downloads a template or exports a versioned JSON character.
2. Player uploads one JSON or CSV file.
3. App validates file type, encoding, size, shape, version, catalog names, and required history.
4. App creates a level-1 draft baseline, validates/finalizes it inside an
   uncommitted transaction, and replays every level-up with the ordinary
   planner/service.
5. App compares supplied current identity and rule-derived data to the replayed
   result; it restores only valid current tracker/inventory values.
6. App changes the resulting character back to `draft`, records an import
   revision, and commits atomically. On any error, it rolls back and reports
   actionable field/rule explanations.

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | The importer accepts only the documented JSON/CSV format and version, and gives a useful error for malformed, unsupported, oversized, or incorrectly encoded files. | `[Validated]` |
| AC-2 | Behavioral | A valid level-1 import resolves canonical Nimble entities, recomputes derived values, and is saved as a draft owned by the importing account (or unowned when no account exists). | `[Validated]` |
| AC-3 | Behavioral | A level 2–20 import is accepted only when it contains exactly one complete, sequential, finalized transition for each level from 2 through its declared level; every transition passes the existing planner/service. | `[Validated]` |
| AC-4 | Negative | Missing, duplicated, out-of-order, incomplete, or illegal progression history cannot create a partial or playable character. | `[Validated]` |
| AC-5 | Negative | Incoming IDs, account ownership, status, previews, and derived values cannot override server-calculated state; a story-based subclass cannot bypass GM approval. | `[Validated]` |
| AC-6 | Edge case | Current HP, wounds, actions, hit dice, resources, gold, and inventory are restored only when valid against recomputed maxima and canonical inventory rules. | `[Validated]` |
| AC-7 | Behavioral | JSON export contains a versioned creation baseline and all level-up inputs required to import the same standard-subclass character again. | `[Validated]` |
| AC-8 | Dependency | Any failed validation rolls back all created records and returns actionable field paths and, for rules errors, rule source references. | `[Validated]` |
| AC-9 | Behavioral | A validated higher-level import remains a draft until the normal finalization gate is used; it can become playable only while its complete finalized progression history still matches its level, and its level cannot be directly edited after import. | `[Validated]` |

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | Level-up inputs completely reconstruct a legal character | A replay differs from supplied stats, skills, spell access, or progression | Reject import and fix the export contract or rules engine before allowing partial recovery |
| FC-2 | Rules names remain stable enough for exact mapping | Valid published data cannot resolve to one canonical record | Add explicit, tested aliases to rules data; do not fuzzy-match silently |
| FC-3 | The import fits in one bounded request | Large files cause memory or request instability | Lower the documented limit or design an asynchronous import workflow separately |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| Nimble rules catalog | Content | In progress | `02-rules-canon.md`; current app catalog is v2.0.1 |
| Character creation legality | Technical | Ready | `05-character-creation.md` |
| Level-up planner and service | Technical | Ready | `06-level-up.md` |
| Character revisions and ownership | Domain | Ready | `03-domain-model.md`, `04-character-lifecycle.md` |
| Rule explanation format | UX | Ready | `07-rules-explanations.md` |

## 11. Open questions / TBDs

None. Arbitrary external formats and cross-ruleset migration are intentionally
deferred.

## 12. Evaluation hooks

- Golden: export a legal level-1 character, import it, and compare canonical state.
- Golden: export/import a character with several sequential level-ups and compare every reconstructed transition input and derived result.
- Negative: missing one level-up, an illegal stat increase, an invalid feature pick, a spoofed account ID/status, and an unauthorized story subclass.
- Edge: invalid current tracker/resource value and an over-capacity inventory.
- Integration: failed import leaves no character, revisions, level-ups, or inventory rows behind.
