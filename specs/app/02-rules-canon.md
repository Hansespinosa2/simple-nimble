# Specification: Rules Canon

> **Spec type:** Domain/data
> **Status:** Draft
> **Decision owner:** Product owner
> **Primary executor:** Engineer plus rules/content curator
> **Last updated:** 2026-09-25

---

## 1. Why this spec exists

The product cannot enforce legality or explain rules unless Nimble's rules exist
as structured, versioned application data. This spec defines what "source of
truth" means for rules content.

The v2.0.1 rules registry uses Core Rules 2.0.1, Heroes 2.0.1, and the
Gamemaster's Guide 2.0 as mechanical sources. The parsed Creator's Kit 1.2 is
design guidance, not a rules authority: its introduction explicitly describes
its suggestions as guidelines rather than a rulebook. Its class-cadence advice
may inform UX or future content authoring, but published 2.0.1 progression
tables remain authoritative for character mechanics.

## 2. Outcome statement

**After this spec is executed:**
The app has a curated, versioned, structured in-app rules database that can drive character legality, recommendations, and rule explanations.

**Verification method:**
Check that creation and level-up decisions can be answered from structured rules
records rather than hard-coded UI logic or freeform text blobs alone.

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| Rules truth should live in a structured in-app rules database | `[Validated]` | Direct user answer |
| Rules should be curated and versioned | `[Validated]` | Implied by structured source-of-truth decision |
| Nimble is the canonical system first | `[Validated]` | Direct user answer |
| House rules should be supported soon | `[Validated]` | Direct user answer |
| Rules explanations should cite exact reason and source | `[Validated]` | Direct user answer |
| Source citations use section references (e.g., Chapter 3, Section 5) | `[Validated]` | Direct user answer |
| Overrides are stored alongside — not replacing — the original canon rule | `[Validated]` | Direct user answer |
| House rules are out of scope for v1 | `[Validated]` | Direct user answer |

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| S-1 | Canonical rules entities | Full structured list — see below |
| S-2 | Rules versioning | The app can identify which ruleset version a character depends on |
| S-3 | Citation metadata | Every enforceable rule can point to its source |
| S-4 | Override model | The system can represent official rule plus approved override paths |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| X-1 | Unstructured prose-only rules import as the long-term model | Prevents legality engine and explanations |
| X-2 | Multi-system rules engine | Product is Nimble-first |
| X-3 | Community-authored open marketplace of rules packs | Too broad for current product phase |
| X-4 | House rules | Out of scope for v1; to be introduced in a later release |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| Rules admin | Publish correct structured rule content | New role implied by product |
| Player | Consume rules indirectly through flows and explanations | Should not have to manage canon directly |
| GM | May later apply campaign-level overrides | Likely future role |

## 7. Flow / state changes

1. Rules source is entered or imported into structured storage.
2. Rules are normalized into entities plus relationships.
3. Each rule element receives source metadata and versioning.
4. Characters reference a specific rules context.
5. Overrides, if present, are stored distinctly from core canon.

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | Any rule required to determine character legality can be queried as structured data, not only read as prose. | `[Assumed: verify]` |
| AC-2 | Behavioral | Each enforceable rule element includes a source reference that can be surfaced in UI explanations. | `[Validated]` |
| AC-3 | Behavioral | A character can be associated with a specific rules version or rules context. | `[Assumed: verify]` |
| AC-4 | Negative | The app does not rely on scattered hard-coded conditionals as the only implementation of game rules. | `[Assumed: verify]` |
| AC-5 | Edge case | If an override conflicts with base canon, the system preserves both the official rule and the active override record. | `[Validated]` |
| AC-6 | Dependency | Creation and level-up specs cannot be finalized until the minimum required rules entities are enumerated. | `[Validated]` |

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | Nimble rules are structured enough for machine evaluation | Key legality checks still depend on human interpretation each time | Stop on new flow work and define missing rule shapes |
| FC-2 | Versioning can remain lightweight | Rule updates break existing characters silently | Add migration and compatibility policy before shipping |
| FC-3 | House rules can fit on top of canon cleanly | Overrides require destructive mutation of base rules | Re-open override model before campaign features proceed |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| Full Nimble rules corpus access | Content | Unknown | Not represented in repo yet |
| Data model for rules entities | Technical | Unknown | See `03-domain-model.md` |
| Editorial process for corrections | Process | Unknown | No owner formalized yet |

## 11. Open questions / TBDs

All TBDs resolved. No open questions remain for this spec.

- **TBD-1** `[Resolved]` — Full entity list extracted from Nimble v2.0.1 PDFs. See S-1 Entity List below.
- **TBD-2** `[Resolved]` — House rules are out of scope for v1; added as X-4.
- **TBD-3** `[Resolved]` — Citations use section references plus a quote snippet.

---

### S-1 Entity List — Nimble v2.0.1 (extracted from Core Rules, Heroes, Gamemaster's Guide)

> **Status:** `[Validated]` — Extracted directly from PDFs. Cross-checked against `03-domain-model.md` §7.

#### 1. Stats

Four stats. Each character has 2 Key Stats (determined by class) and 2 Secondary Stats.

| Stat | Abbreviation | Affects |
|---|---|---|
| Strength | STR | Weapon damage (STR weapons), HP recovery, Concentration, STR saves, carrying capacity, Might skill |
| Dexterity | DEX | Weapon damage (DEX weapons), Initiative, DEX saves, Armor (unarmored/leather), Stealth, Finesse skills |
| Intelligence | INT | Languages known (+1/point), spellcasting, wand use, INT saves, Arcana/Examination/Lore skills |
| Will | WIL | Spellcasting, WIL saves, Insight/Influence/Naturecraft/Perception skills |

**Stat arrays (creation-time choice — one of three):**
- Standard: +2, +2, +0, –1
- Balanced: +2, +1, +1, +0
- Min-Max: +3, +1, –1, –1

Maximum stat value: +5.

---

#### 2. Skills (10)

Each skill is derived from a stat. Initial value = stat bonus. +4 extra skill points at level 1 distributed freely. +1 skill point per level; can also move 1 existing point per level. Maximum skill value: +12.

**Source confidence:** Core Rules 2.0.1 (p. 20) grants 4 additional skill points at level 1. Core Rules (p. 21) explicitly grants 1 skill point whenever a hero gains a level and allows an optional 1-point transfer, provided the skill losing the point remains nonnegative. The app's per-level skill-point grant and transfer match that rule. Heroes (p. 56) separately lets a Songweaver use the transfer on a Safe Rest.

| Skill | Governing Stat |
|---|---|
| Arcana | INT |
| Examination | INT |
| Finesse | DEX |
| Influence | WIL |
| Insight | WIL |
| Lore | INT |
| Might | STR |
| Naturecraft | WIL |
| Perception | WIL |
| Stealth | DEX |

---

#### 3. Classes (11)

Each class record contains: Key Stats (2), Hit Die size, Starting HP, Save advantages (+/–), Armor proficiency, Weapon proficiency, Starting gear, Class resource type and formula, and a level 1–20 progression table.

| Class | Key Stats | Hit Die | Starting HP | Saves |
|---|---|---|---|---|
| Berserker | STR, DEX | d12 | 20 | STR+, INT– |
| The Cheat | DEX, INT | d6 | 10 | DEX+, WIL– |
| Commander | STR, INT | d10 | 17 | STR+, DEX– |
| Hunter | DEX, WIL | d8 | 13 | DEX+, INT– |
| Mage | INT, WIL | d6 | 10 | INT+, STR– |
| Oathsworn | STR, WIL | d10 | 17 | STR+, DEX– |
| Shadowmancer | INT, DEX | d8 | 13 | INT+, WIL– |
| Shepherd | WIL, STR | d10 | 17 | WIL+, DEX– |
| Songweaver | WIL, INT | d8 | 13 | WIL+, STR– |
| Stormshifter | WIL, DEX | d8 | 13 | WIL+, STR– |
| Zephyr | DEX, STR | d8 | 13 | DEX+, INT– |

---

#### 4. Class Resources (per class)

Each class has one or more special resource pools that must be modeled for legality.

| Class | Resource | Formula / Scaling |
|---|---|---|
| Berserker | Fury Dice | Starts d4; scales to d6 (L6), d8 (L9), d10 (L13), d12 (L17); max = KEY; gained by Raging |
| The Cheat | (No pool; ability-based) | Uses per-ability counters (1/turn, 1/day, 1/Safe Rest) |
| Commander | Combat Dice; Coordinated Strike uses | Combat Dice: gain STR dice on Initiative from L4; starts d6 and scales to d8 (L5), d10 (L9), d12 (L13), d20 (L17); pool size = STR + upgrades. Coordinated Strike: INT uses/Safe Rest, +1 at L9, L13, L17, and Champion of the Vanguard L7; Master Commander L5 and Vanguard L11 each refund 1 spent use on Initiative, expiring at encounter end. Heroes 2.0.1, pp. 19–23 |
| Hunter | Thrill of the Hunt charges; Shadowpath Ambusher advantage; Wild Heart High Ground movement | TotH charges are gained on quarry triggers; Shadowpath gains 1 at Initiative at L15. Ambusher at L3 may use Hunter's Mark for free at Initiative and grants advantage on the first attack each encounter, tracked as a separate one-use counter. Wild Heart at L3 automatically records its free half-speed movement trigger at Initiative and whenever one or more TotH charges are gained. Save distinct gain events separately. Movement is not banked; map position and difficult-terrain handling remain table-resolved. Heroes 2.0.1, pp. 26, 28-29 |
| Mage | Mana | (INT×3)+LVL; recharges on Safe Rest; Elemental Surge grants +WIL temporary mana on Initiative from L5, plus 1d4 at L10 and 2d4 at L17; unused mana expires at encounter end. Control's L11 Steel Will may reroll each Elemental Surge die showing 1 once. Heroes 2.0.1, pp. 32, 35 |
| Oathsworn | Judgment Dice (2d6 → d8 → d10 → d12 → d20) + Lay on Hands pool (5×LVL) | Judgment triggered by being attacked |
| Shadowmancer | Pilfered Power uses (DEX/Safe Rest) | Patron penalty if exceeded; Pact of the Red Dragon regains up to one spent use on Initiative at L11, expiring at encounter end. Heroes 2.0.1, pp. 44, 47 |
| Shepherd | Mana; Searing Light; subclass charges | Mana: (WIL×3)+LVL/Safe Rest. Searing Light: WIL uses/Safe Rest. Sacred Grace Light Bearer refunds 1 spent Searing Light use on Initiative (encounter-only); Luminary of Mercy Empowered Conduit refunds 1, and Luminary of Malice Conduit of Death recharges Veilwalker's Blessing at Initiative, each expiring at encounter end. Heroes 2.0.1, pp. 49, 52–53 |
| Songweaver | Mana + Inspiration | Mana: (INT×3)+LVL/Safe Rest; Inspiration: 2×WIL/Safe Rest; Quick Wit regains up to 2 spent uses on Initiative at L3, expiring at encounter end. Heroes 2.0.1, p. 56 |
| Stormshifter | Mana + Beastshift charges | Mana: (WIL×3)+LVL; Beastshift: DEX charges/Safe Rest. Circle of Fang & Claw's level-3 Swiftshift lets the player choose a free Beastshift or move when Initiative is rolled; free Beastshifting grants no temporary HP. Heroes 2.0.1, pp. 61, 65 |
| Zephyr | Bursts of Speed | At level 2, gain DEX Bursts when rolling Initiative (plus 1 at level 20); at level 3+, gain 1 whenever you gain a Wound. No maximum is stated for the encounter pool. The level-4 Unyielding Resolve ignores the first Wound each encounter, but Wound-triggered abilities still trigger. Heroes 2.0.1, pp. 67–69 |

---

#### 5. Spell Tier Unlocks (per class)

Spellcasting classes unlock higher spell tiers at specific levels. Non-casters have no class-wide tier schedule. These levels are transcribed from the published class progressions:

| Class | Cantrips | T1 | T2 | T3 | T4 | T5 | T6 | T7 | T8 | T9 | Source |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Mage | L1 | L2 | L4 | L6 | L8 | L10 | L12 | L14 | L16 | L18 | Heroes 2.0.1, pp. 31–35 |
| Oathsworn | L2 | L2 | L4 | L6 | L8 | L10 | L13 | L17 | — | — | Heroes 2.0.1, pp. 37–41 |
| Shadowmancer | L1 | L2 | L5 | L7 | L10 | L13 | L16 | L19 | — | — | Heroes 2.0.1, pp. 43–47 |
| Shepherd | L1 | L2 | L4 | L6 | L8 | L10 | L12 | L14 | L16 | L18 | Heroes 2.0.1, pp. 49–53 |
| Stormshifter | L1 | L2 | L4 | L6 | L8 | L10 | L12 | L14 | L16 | L18 | Heroes 2.0.1, pp. 61–65 |
| Songweaver | L1 | L2 | L4 | L6 | L8 | L10 | L12 | L14 | L16 | L18 | Heroes 2.0.1, pp. 55–59 |

Non-casters (Berserker, The Cheat, Commander, Hunter, Zephyr): no mana or tier unlocks unless granted by subclass or background.

---

#### 6. Subclasses (chosen at Level 3 unless story-based)

| Class | Subclass A | Subclass B | Story-Based |
|---|---|---|---|
| Berserker | Path of the Red Mist | Path of the Mountainheart | — |
| The Cheat | Silent Blade | Scoundrel | — |
| Commander | Bulwark | Vanguard | Spellblade |
| Hunter | Shadowpath | Wild Heart | Beastmaster |
| Mage | Chaos | Control | — |
| Oathsworn | Oath of Vengeance | Oath of Refuge | Oathbreaker |
| Shadowmancer | Pact of the Red Dragon | Pact of the Abyssal Depths | Reaver |
| Shepherd | Luminary of Mercy | Luminary of Malice | — |
| Songweaver | Herald of Snark | Herald of Courage | — |
| Stormshifter | Circle of Fang & Claw | Circle of Sky & Storm | — |
| Zephyr | Way of Flame | Way of Pain | — |

Each subclass grants features at levels 3, 7, 11, and 15.

The four story-based subclasses are not level-3 picks. A GM may grant the listed
story-based subclass at a story moment, replacing the character's current
subclass. In the app, that exception is available only to the GM of a campaign
where the sheet is shared, requires a story note, and records the old/new
subclass, GM, campaign, and rules citation in the audit history.

Spellblade's Deep Knowledge is a level-based spell-choice feature, not just a
displayed feature name: at levels 3, 7, 11, and 15 it grants one spell of up to
tiers 1, 2, 3, and 4 respectively, plus one Utility Spell at each milestone.
Those pools, tier ceilings, counts, source quotes, and citations are structured
in the rules catalog. A story change requires all Deep Knowledge picks already
earned by the character, stores those choices in both the character's
progression ledger and the audit record, and exposes later picks in level-up.

Spellblade's level-3 Firebrand also permits a free Enchant Weapon cast when
Initiative is rolled. The Initiative form can record whether the player takes
that option and the named weapon or wielder; it writes that choice into the
Initiative revision with the Heroes citation. The app records the free base
cast only: applying the spell's effects, concentration, and any paid upcast
remains a table ruling and is not simulated by the character sheet.

Shadowpath's level-3 Ambusher offers the same Initiative-time record for its
free Hunter's Mark, including the named quarry/quarries. Its first-attack
advantage is a separate encounter counter that can be spent once through an
explicit sheet action; the attack roll and Hunter's Mark effects remain
table-resolved. At level 15, Ambusher and Apex Predator grants are both applied
on Initiative, with the latter adding its separate Thrill of the Hunt charge.

Circle of Fang & Claw's level-3 Swiftshift offers a player choice at Initiative:
record a free Beastshift or a free move. The sheet records which option was
chosen, does not spend a Beastshift charge, and does not simulate the form or
movement; it explicitly preserves the rule that the free Beastshift grants no
temporary HP.

Wild Heart's level-3 I Have the High Ground triggers free movement when
Initiative is recorded and whenever one or more Thrill of the Hunt charges are
gained. Each saved charge increase automatically records one triggered
movement event; save separate gain events separately.
Movement is not banked for later. Both Initiative and charge-gain records
cite Heroes 2.0.1, p. 29. The sheet does not place a token on a battle map or
resolve distance, speed modifiers, or difficult-terrain effects; the
player/GM resolves the up-to-half-speed movement, ignoring difficult terrain,
at the table.

Beastmaster also records its source-defined setup at the story change: an animal
name and Small/Medium/Large size, plus a reconfirmation of the first two Thrill
of the Hunt choices against the ordinary pool and the two companion options
Go for the Throat! and Protect Me! The selected options are recorded with both
their standard-pool and subclass citations. The app does not create companion
HP or movement trackers because the book explicitly abstracts them. It surfaces
the selected size's abilities, level-based damage/uses/action costs and passive
features with a page citation, and creates encounter-use counters only for
limited abilities actually granted to that companion. The player's Encounter
End action refreshes only counters whose source says they reset when an encounter
ends; it does not refill Safe Rest or daily-use resources.

---

#### 7. Selectable Feature Pools (per class)

Each class has one or more pools of abilities from which the player picks at designated levels.

| Class | Pool Name | Pool Size | Choice Schedule | Source |
|---|---|---|---|---|
| Berserker | Savage Arsenal | 12 abilities | L4; additional at L6, L8, L10, L12, L14, L16 | Heroes 2.0.1, p. 10 |
| The Cheat | Underhanded Ability | 10 abilities | L4; additional at L6, L8, L10, L12, L14, L16, L18 | Heroes 2.0.1, p. 16 |
| Commander | Coordinated Strike! | Granted automatically | L1; not a selectable Commander’s Order | Heroes 2.0.1, p. 19 |
| Commander | Commander's Orders | 5 selectable orders | Choose 2 at L2 | Heroes 2.0.1, p. 19 |
| Commander | Combat Tactics | 5 tactic types | Choose 1 at L4 | Heroes 2.0.1, p. 22 |
| Commander | Combat Ability | Commander’s Orders or Combat Tactics not already chosen, or +1 max Combat Dice (repeatable) | Choose 1 at L6, L8, L10, L12, and L16 | Heroes 2.0.1, pp. 20, 22 |
| Commander | Weapon Mastery | 3 types (Slashing/Bludgeoning/Piercing) | Choose at L6 and L10; complete mastery is granted at L14 | Heroes 2.0.1, p. 22 |
| Hunter | Thrill of the Hunt | 14 abilities | L2 (2 choices); additional at L4, L6, L8, L12, L14 | Heroes 2.0.1, p. 28 |
| Mage | Spellshaper | 8 abilities | L4 (2 choices); +1 at L9, L13 | Heroes 2.0.1, p. 34 |
| Oathsworn | Sacred Decree | 10 decrees | L3; additional at L6, L9, L12, L14, L16 | Heroes 2.0.1, p. 40 |
| Shadowmancer | Lesser Shadow Invocation | 10 invocations | L3; +1 at L8, L11 | Heroes 2.0.1, p. 46 |
| Shadowmancer | Greater Shadow Invocation | 11 invocations | L4; +1 at L6, L9, L14, L18 | Heroes 2.0.1, p. 46 |
| Shepherd | Sacred Grace | 8 graces | L5 (2 choices); +1 at L9 and L13 | Heroes 2.0.1, p. 52 |
| Songweaver | A “People Person” | 4 unique NPCs | Choose 2 at L5 | Heroes 2.0.1, p. 58 |
| Songweaver | Lyrical Weaponry | 5 abilities | L4; +1 at L9, L13, L17 | Heroes 2.0.1, p. 58 |
| Stormshifter | Chimeric Boon | 9 boons | L6 (2 choices); +1 at L9, L12, L17 | Heroes 2.0.1, p. 64 |
| Zephyr | Martial Arts | 11 abilities | L4; +1 at L6, L8, L10, L12, L14, L16, L18 | Heroes 2.0.1, p. 70 |

---

#### 8. Stat Increases (per class, per level)

Two types: Key Stat Increase (+1 to one of the two Key Stats) and Secondary Stat Increase (+1 to one of the two Secondary Stats). Schedule varies per class but follows the same general pattern: Key at L4/L8/L12/L16, Secondary at L5/L9/L13/L17, with class-specific variations.

---

#### 9. Ancestries

**Common Ancestries (5):**

| Ancestry | Size | Trait Summary |
|---|---|---|
| Human | Medium | +1 all skills and Initiative |
| Dwarf | Medium | +2 max Hit Dice, +1 max Wounds, –1 Speed; Dwarvish if INT ≥ 0 |
| Elf | Medium | Advantage on Initiative, +1 Speed; Elvish if INT ≥ 0 |
| Halfling | Small | +1 Stealth; reroll any failed save 1/Safe Rest |
| Gnome | Small | Allow ally reroll of 1 die (resets on heal to max HP), –1 Speed; Dwarvish if INT ≥ 0 |

**Exotic Ancestries (19):**

| Ancestry | Size | Trait Summary |
|---|---|---|
| Bunbun | Small | Hop Speed for free 1/encounter after Interpose/Defend |
| Dragonborn | Medium | +1 Armor; LVL+KEY bonus damage 1/encounter or 1/Wound; Draconic if INT ≥ 0 |
| Fiendkin | Medium | 1 neutral save becomes advantaged; Infernal if INT ≥ 0 |
| Goblin | Small | Free 2-space move after being targeted 1/attack; Goblin if INT ≥ 0 |
| Kobold | Small | Force enemy reroll 1/encounter; +3 Influence with friendlies; advantage vs dragons; Draconic if INT ≥ 0 |
| Orc | Medium | Set HP to LVL instead of 0, 1/Safe Rest; +1 Might; Goblin if INT ≥ 0 |
| Birdfolk | Small/Med | Fly Speed (Leather or lighter only); Vicious crits against you; forced movement × 2 |
| Celestial | Medium | Disadvantaged save becomes Neutral; Celestial if INT ≥ 0 |
| Changeling | Medium | +2 shifting skill points; take any ancestry appearance 1/day |
| Crystalborn | Medium | On Defend: gain KEY armor + deal KEY damage back, 1/encounter |
| Dryad/Shroomling | Small/Med | On Wound gained: all adjacent enemies Dazed; Elvish if INT ≥ 0 |
| Half-Giant | Large | Force crit reroll 1/encounter; +2 Might; Dwarvish if INT ≥ 0 |
| Minotaur/Beastfolk | Medium | Charge: push creature in path on 4-space move, 1/turn |
| Oozeling/Construct | Small/Med | +1 Hit Die size; always heal max from HD; always heal min from magic healing |
| Planarbeing | Medium | On Defend: spend 1 Wound to ignore all damage; –2 max Wounds |
| Ratfolk | Small | +2 Armor if moved on last turn |
| Stoatling | Small | Additional d6 per size category larger on single-target attacks (and target does the same) |
| Turtlefolk | Small/Med | +4 Armor, –2 Speed |
| Wyrdling | Small | Ally tiered spell may roll on Chaos Table, 1/encounter |

---

#### 10. Backgrounds (~24)

Backgrounds grant one or more special abilities. Some have stat prerequisites checked at character creation.

**Prerequisite-gated backgrounds:**
- So Dumb I'm Smart Sometimes: requires INT ≤ 0 at creation
- Wily Underdog: requires STR ≤ 0 at creation
- Bumblewise: requires WIL ≤ 0 at creation
- Accidental Acrobat: requires DEX ≤ 0 at creation

**Full list:** Back Out of Retirement, Devoted Protector, Academy Dropout (grants 1 Utility Spell), Made a BAD Choice, Haunted Past, Ear to the Ground, What? I've Been Around, Acrobat, Wild One, Fey Touched, Survivalist, Home at Sea, At Home Underground, Raised by Goblins, History Buff, (Former) Con Artist, (Secretly) Undead, Taste for the Finer Things, Fearless, So Dumb I'm Smart Sometimes, Wily Underdog, Bumblewise, Accidental Acrobat, Tradesman/Artisan.

---

#### 11. Languages (10)

| Language | Default Speakers |
|---|---|
| Common | All — every hero knows this automatically |
| Dwarvish | Dwarves, Gnomes, Giants |
| Elvish | Elves, Fey, Sylvan |
| Goblin | Goblins, Orcs |
| Infernal | Fiends, cultists |
| Thieves' Cant | Rogues, scoundrels |
| Celestial | Celestials, priests |
| Draconic | Dragons, Dragonborn, Kobolds |
| Primordial | Elementals, Ancient Beings |
| Deep Speak | Underworld dwellers |

Derivation rule: Every hero knows Common. Each point of INT grants +1 additional language. Certain ancestries and backgrounds grant specific languages if INT ≥ 0.

---

#### 12. Spells

**Six schools of magic.** Each school has cantrips and up to 9 tiers of tiered spells.

**School summaries:**
- **Fire**: High consistent damage at medium range. Cantrips: Flame Dart, Heart's Fire. Tiers 1–9 (Ignite, Enchant Weapon, Flame Barrier, Pyroclasm, Fiery Embrace, [T6], Living Inferno, [T8], Dragonform).
- **Ice**: Medium damage at long range, battlefield control. Cantrips: Ice Lance, Snowblind. Tiers 1–9 (Frost Shield, Shatter, Cryosleep, Rimeblades, Arctic Blast, [T6], Glacier Strike, Arctic Annihilation, [T9]).
- **Lightning**: High damage at long range, teleport effects. Cantrips: Zap, Overload. Tiers 1–9 (Arc Lightning, Alacrity, Stormlash, Electrickery, Electrocharge, Ride the Lightning, [T7–8], Seething Storm).
- **Wind**: Movement control, slashing multi-target. Cantrips: Razor Wind, Breath of Life, Vicious Mockery (Songweaver only). Tiers 1–7 (Blustery Gale, Barrier of Wind, Fly, Eye of the Storm, Updraft, Thousand Cuts, Boisterous Winds).
- **Radiant**: Healing, revival, obliterate undead. Cantrips: Rebuke, True Strike. Tiers 1–9 (Heal, Warding Bond, Shield of Justice, Condemn, Vengeance, Sacrifice, [T7–8], Redeem). Shepherd-only: Lifebinding Spirit (T1).
- **Necrotic**: Summon minions, drain life force. Cantrips: Entice, Withering Touch, Shadow Blast (Shadowmancer), Summon Shadows (Shadowmancer). Tiers 1–4+ (Shadow Trap, Dread Visage, Vampiric Greed, Greater Shadow, ...).

**Per-spell record shape:**

| Field | Description |
|---|---|
| name | Spell name |
| school | Fire / Ice / Lightning / Wind / Radiant / Necrotic |
| tier | Cantrip or 1–9 |
| mana_cost | Equal to tier; 0 for cantrips |
| action_cost | Number of actions (1–5) |
| target_type | Single Target / AoE / Self / Multi-target / Special |
| range_or_reach | Distance in spaces (Range = ranged with melee-adjacent penalty; Reach = close without penalty) |
| damage_formula | Dice expression and damage type (e.g., 4d10, d66) |
| condition_applied | Any condition inflicted (e.g., Smoldering, Slowed, Blinded) |
| upcast_rule | Effect per additional mana spent |
| high_level_scaling | Automatic scaling at certain character levels |
| class_restriction | If not universally available (e.g., Vicious Mockery = Songweaver only) |
| source_ref | Chapter and section, plus quote snippet |

Spells accessible to a character are determined by: the spell schools their class knows, and the highest tier they have unlocked at their current level.

---

#### 13. Derived Value Formulas

These must be calculable from structured data — no manual calculation required.

| Derived Value | Formula |
|---|---|
| Armor (unarmored) | DEX; Zephyr uses DEX + STR. Zephyr's level-13 Iron Defense doubles Armor while unarmored. |
| Armor (cloth or leather) | Item value + DEX |
| Armor (mail) | Item value + min(DEX, 2) |
| Armor (plate) | Listed flat item value; no DEX |
| Shield | Add the equipped shield's listed Armor to total Armor; optional Deflect can instead reduce one attack's damage by that value for free once per round. |
| Initiative | DEX (default; some classes/ancestries modify) |
| Speed | 6 (default; modified by ancestry/equipment/features) |
| Max actions per turn | 3 by default; permanent class features modify this (Zephyr's level-20 Windborne grants +1 action, while Dying the maximum is 2). |
| Max Wounds | 6 (default; modified by ancestry/class features) |
| Inventory Slots | 10 + STR |
| Starting equipment | Listed class gear or 50 gp × starting level; carried currency uses 1 slot per 500 gp |
| Languages known | 1 (Common) + max(INT, 0) extra + ancestry/background grants |
| Save DC (for hero-caused effects) | 10 + KEY stat |
| Mana pool max | Class-specific formula (e.g., INT×3+LVL for Mage; WIL×3+LVL for Shepherd/Stormshifter) |
| HP on level-up | Roll Hit Die with advantage (add the higher result to max HP) |
| Hit Dice amount | Equal to current level (default) |
| Skill initial value | Governing stat bonus (e.g., Stealth starts at DEX) |

---

#### 14. Equipment

**Armor types (5 categories):**
Cloth (4 tiers), Leather (4 tiers), Mail (4 tiers), Plate (4 tiers), Shields (4 tiers). Each has armor value, STR requirements, and cost. STR requirements are required to equip the item. Unarmored formulas and equipment Armor bonuses follow the category-specific table above (Core Rules 2.0.1, pp. 32–33; Zephyr, Heroes 2.0.1, pp. 67–68).

**Weapons:**
- Melee (14 types): Dagger, Sickle, Club/Mace, Hand Axe, Short Sword, Rapier, Staff, Longsword, Battleaxe, Pole Hammer, Glaive, Spear, Greatmaul, Greataxe, Greatsword
- Ranged (7 types): Sling, Javelins, Throwing Hammers, Shortbow, Longbow, Crossbow, Handheld Ballista

**Weapon properties:** 2-handed, Light, Load, Reach, Range, Thrown, Vicious. Each affects legality of use and combat calculations.

**Equipment proficiency per class:** Each class defines which armor tiers and weapon categories are covered. Heroes may use equipment without proficiency; weapons used without proficiency cannot crit, while Defending in worn armor without proficiency costs +1 action (Core Rules 2.0.1, p. 32).

---

#### 15. Boons

Chosen at level 19 (Epic Boon). Minor and Major Boons are optionally used as quest rewards or as alternatives to stat increases at certain levels.

| Tier | Count | Examples |
|---|---|---|
| Minor | ~9 | +1 Initiative, +1 max mana, +4 HP, +1 Speed, +1 skill point |
| Major | ~20 | +2 Armor, +4 max mana, learn 1 Cantrip, advantage on attacks vs unengaged targets |
| Epic | 12 | Chosen at level 19; see the 12 source-defined options below. |

All classes grant one Epic Boon at level 19. The level-up flow requires one of
the 12 options on Gamemaster's Guide 2.0, p. 23, records the choice with the
Heroes 2.0.1 progression citation, and displays its source-described effect on
the character sheet. Epic Stats is interpreted as an explicit exception to the
Core Rules' *typical* +5 stat maximum because the boon grants +1 without stating
a cap. Epic Speed, Epic Foresight, Epic Defense, Epic Mind, Epic Stats, and Epic
Stamina update the corresponding derived values. Epic Agility, Epic Knowledge,
Epic Resistance, and Epic Foresight's first-attack advantage have use counters;
encounter-limited counters refresh when an encounter ends. Other situational
attack/save effects remain reference-only. Epic Mana can substitute Mana for
Field Rest healing in the sheet flow; healing from spells and other external
sources must still be recorded manually because the app does not resolve them.

---

#### 16. Conditions (18 named conditions + minor statuses)

Core Rules 2.0.1, p. 11 lists 18 distinct named conditions (17 bullets, with Grappled/Restrained grouped together). Bloodied, Dying, and Wounded are mechanically derived from tracked HP/Wounds; the other 15 named conditions can be recorded during play. The character sheet surfaces the three derived states automatically.

Core Rules 2.0.1, p. 9 also requires a hero reduced from positive HP to 0 HP to gain 1 Wound and become Dying until HP is regained. The game-state tracker records that Wound on the transition (not on repeated saves at 0 HP), and shows Dying's action limit with source-defined exceptions: Berserker's level-4 Enduring Rage allows a maximum of 2 actions (Heroes 2.0.1, p. 8), as does Zephyr's level-20 capstone (Heroes 2.0.1, p. 69). It does not enforce action limits or automate the other tactical effects of Dying.

The Wounds tracker also surfaces the Core Rules' default death threshold of 6 Wounds. The rules allow abilities to change that number; the tracker does not calculate feature-specific or situational exceptions.

Named conditions: Blinded, Bloodied, Charmed, Dazed, Dying, Frightened, Grappled, Hampered, Incapacitated, Invisible, Petrified, Poisoned, Prone, Restrained, Riding, Slowed, Taunted, Wounded.

Minor statuses (for example, Charged, Distracted, and Smoldering) do nothing on their own and are referenced by spell and ability prerequisites. The tracker records other conditions and statuses as notes; it does not automate their effects or durations.

---

#### 17. Cross-check against `03-domain-model.md` §7

| Domain Model Entity | Nimble Reality | Status |
|---|---|---|
| `Class` | ✅ 11 classes with full progression tables | Confirmed |
| `Race` | ✅ Exists as `Ancestry` in Nimble — 5 common + 14 exotic | Rename to `Ancestry` |
| `Spell` | ✅ 6 schools × up to 9 tiers + cantrips; richer than expected | Confirmed; needs per-spell record shape |
| `Feature` | ✅ ClassFeature (fixed per level), SelectableFeature (from pool), SubclassFeature | Split into 3 subtypes |
| `Prerequisite` | ✅ Stat minimums (equipment, backgrounds), proficiency checks | Confirmed |
| `ProgressionRule` | ✅ Level 1–20 table per class, spell tier unlock table, stat increase schedule | Confirmed |
| `Background` | ➕ Not in domain model — needs addition | **Add to domain model** |
| `StatArray` | ➕ Not in domain model — creation-time choice | **Add to domain model** |
| `DerivedValueFormula` | ➕ Not in domain model — required for auto-calculation | **Add to domain model** |
| `SelectableFeaturePool` | ➕ Not in domain model — lists like Savage Arsenal | **Included under Feature** |
| `Language` | ➕ Not in domain model — needed for legality (languages determined by INT + grants) | **Add to domain model** |
| `Boon` | ➕ Not in domain model — Minor/Major/Epic Boons chosen at level 19 | **Add to domain model** |
| `Equipment` / `EquipmentProficiencyRule` | ⚠️ Partially represented (StatSet, SkillSet, TraitSet) — needs reframing | **Reframe in domain model** |

**Recommended domain model additions** (for `03-domain-model.md` §7):
- `Background`
- `StatArray`
- `DerivedValueFormula`
- `Language`
- `Boon` (Minor / Major / Epic)
- Rename `Race` → `Ancestry`
- Split `Feature` into `ClassFeature`, `SelectableFeature`, `SubclassFeature`
- Reframe equipment entities to include `EquipmentProficiencyRule`

## 12. Evaluation hooks

- Rule coverage matrix: every level-up decision cites one or more canonical rules
- Schema coverage: every creation field maps to a structured rule or explicit freeform field
- Regression test: updating a rule version does not silently change prior character legality
