# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end


### CHARACTERS ###
Character.create(
  name: "Gorn",
  race: "Orc",
  nimble_class: "Zephyr",
  level: 5,
  background: "Angry",
  description: "Gorn is a fierce orc Zephyr, known for his swift movements and relentless aggression. His imposing presence and quick temper make him a formidable opponent on the battlefield.",
  languages: "Common, Orcish"
)

Character.create(
  name: 'Luna Banana-Hammock',
  race: "Birdfolk",
  nimble_class: "Stormweaver",
  level: 10,
  background: "Inspirational leader",
  description: "Luna is the lone survivor of an ancient birdfolk civilization, carrying the wisdom and sorrow of her lost people. Her resilience and leadership inspire those around her, and her mastery of storm magic reflects the enduring spirit of her heritage.",
  languages: "Common, Bird, Elvish"
)

Character.create(
  name: "David Andersen",
  race: "Human",
  nimble_class: "Commander (Spellblade)",
  level: 4,
  background: "Fearless",
  description: "At 22, David led his first campaign against a band of Infernal cultists who had infiltrated Rawa City's lower districts, seeking to tear open a rift to the Abyss. It was there that he learned Infernal, a language he would come to despise yet master, using it to outmaneuver his enemies. The battle was brutal, and though victorious, David was left with a deep scar across his chest, a constant reminder of the city's vulnerability.
                His heroics earned him the title of Warden of Rawa City, a position once held by his father. But unlike his predecessors, David did not simply sit behind the city's walls—he patrolled the borders, fought alongside his soldiers, and personally ensured that Rawa remained standing.
                David is a calculated warrior, confident yet pragmatic. He is respected by his people, not for his lineage, but for his actions on the battlefield. He values loyalty above all else, which is why he has a close bond with his partner, Karisa Dunefall, a fierce warrior who stands as his second-in-command.
                At 25, David met Karisa Dunefall, a tiefling scholar from Cois Oasis. Karisa, an outcast from her people, had forged her own path as a hostage negotiator for the palace. When Rawa came under siege by a coalition of raiders and dark mages, she was sent by Cois Oasis as a symbol of their strong alliance.
                David led the patrol unit alongside Karisa in the city's streets, fighting invaders and driving them out of the city. By the battle's end, they had saved each other's lives more times than either could count. It was an unspoken bond, forged in fire and blood.
                Despite his hardened exterior, David has a deep compassion for his people. He will always put their lives before his own, even if it means making sacrifices that weigh heavily on his soul.
                Of all his weapons and abilities, Kai remains David's greatest asset. The golden-furred familiar has been with him since childhood, acting as both a guardian and a trusted companion. Their bond is unbreakable, and in battle, Kai serves as both a healer and a protector, ensuring David fights at his full potential.
               ",
  languages: "Common, Infernal"
)

### SPELLS ###
Spell.create(
  school: "Fire",
  name: "Flame Dart",
  tier: 0,
  target: 1,
  range: 8,
  action_cost: 1,
  damage: "1d10",
  description: "On crit: Smoldering.",
  casting_time: 0,
  high_level: "+5 damage every 5 levels.",
  upcast: nil
)

Spell.create(
  school: "Fire",
  name: "Heart's Fire",
  tier: 0,
  target: 1,
  range: 4,
  action_cost: 1,
  damage: nil,
  description: "Give an ally within range an extra action. Spend 1 mana to cast this when it is not your turn.",
  casting_time: 0,
  high_level: "+1 range every 5 levels.",
  upcast: nil
)

Spell.create(
  school: "Fire",
  name: "Ignite",
  tier: 1,
  target: 1,
  range: 8,
  action_cost: 2,
  damage: "4d10",
  description: "Only targets a Smoldering creature; on hit, ends Smoldering.",
  casting_time: 0,
  high_level: nil,
  upcast: "+10 damage."
)

Spell.create(
  school: "Fire",
  name: "Enchant Weapon",
  tier: 2,
  target: 1,
  range: 1,
  action_cost: 1,
  damage: nil,
  description: "Concentration: Up to 1 minute. A touched weapon is wreathed in magical flame; it deals +KEY damage and inflicts Smoldering on crit.",
  casting_time: 0,
  high_level: nil,
  upcast: "+KEY damage."
)

Spell.create(
  school: "Fire",
  name: "Flame Barrier",
  tier: 3,
  target: 0,
  range: 0,
  action_cost: 1,
  damage: "KEY (ignores armor)",
  description: "Self. Reaction: When attacked, Defend for free. Until the start of your next turn, melee attackers take KEY damage (ignores armor) and gain Smoldering.",
  casting_time: 0,
  high_level: nil,
  upcast: "+KEY damage."
)

Spell.create(
  school: "Fire",
  name: "Pyroclasm",
  tier: 4,
  target: 0,
  range: 3,
  action_cost: 2,
  damage: "2d20+10 (ignores armor)",
  description: "Others within reach take damage on a failed DEX save; half on success. Smoldering creatures automatically fail.",
  casting_time: 0,
  high_level: nil,
  upcast: "+1 reach, +2 damage."
)

Spell.create(
  school: "Fire",
  name: "Fiery Embrace",
  tier: 5,
  target: 0,
  range: 8,
  action_cost: 2,
  damage: nil,
  description: "Concentration: Up to 1 minute. While within reach: choose 1 ally to gain the effects of Enchant Weapon. Enemies gain Smoldering, lose damage resistance, and their damage immunity is reduced to resistance.",
  casting_time: 0,
  high_level: nil,
  upcast: "+1 ally."
)

Spell.create(
  school: "Fire",
  name: "Living Inferno",
  tier: 7,
  target: 0,
  range: 0,
  action_cost: 3,
  damage: nil,
  description: "Gain the effects of Flame Barrier until your next turn. At the end of this turn and your next turn, cast Pyroclasm for free.",
  casting_time: 0,
  high_level: nil,
  upcast: "Also upcasts Flame Barrier and Pyroclasm."
)

Spell.create(
  school: "Fire",
  name: "Dragonform",
  tier: 9,
  target: 0,
  range: 0,
  action_cost: 5,
  damage: nil,
  description: "Transform into a Huge dragon: gain 3 actions, fly speed 12, LVL Armor, and 10×LVL temp HP. Actions: Tooth & Claw (Action, reach 2): 1d20+LVL damage (ignores armor), inflicts Smoldering. Immolating Breath (2 actions, cone 8): DC 20 DEX save, KEY d20 damage, half on save; Smoldering targets fail. Maintain while temp HP remain (max 10 minutes). When it ends, drop to 0 HP.",
  casting_time: 0,
  high_level: nil,
  upcast: nil
)


Spell.create(
  school: "Ice",
  name: "Ice Lance",
  tier: 0,
  target: 1,
  range: 12,
  action_cost: 1,
  damage: "1d6 cold or piercing damage",
  description: "On hit: Slowed.",
  casting_time: 0,
  high_level: "+3 damage every 5 levels.",
  upcast: nil
)

Spell.create(
  school: "Lightning",
  name: "Zap",
  tier: 0,
  target: 1,
  range: 12,
  action_cost: 1,
  damage: "2d8",
  description: "On miss: the lightning fails to find ground, and strikes you instead.",
  casting_time: 0,
  high_level: "+6 damage every 5 levels.",
  upcast: nil
)

Spell.create(
  school: "Wind",
  name: "Razor Wind",
  tier: 0,
  target: 1,
  range: 12,
  action_cost: 1,
  damage: "1d4 slashing",
  description: "Vicious: roll 1 additional die whenever you roll crit damage. Also damages up to 1 adjacent target.",
  casting_time: 0,
  high_level: "+2 damage every 5 levels.",
  upcast: nil
)

Spell.create(
  school: "Radiant",
  name: "Rebuke",
  tier: 0,
  target: 1,
  range: 4,
  action_cost: 1,
  damage: "1d6 (ignores armor)",
  description: "Does not miss. Deals double damage against undead or cowardly targets (Frightened or behind cover).",
  casting_time: 0,
  high_level: "+2 damage every 5 levels.",
  upcast: nil
)

Spell.create(
  school: "Necrotic",
  name: "Entice",
  tier: 0,
  target: 1,
  range: 8,
  action_cost: 1,
  damage: "1d4 (ignores armor)",
  description: "On hit: target moves 2 spaces closer to you.",
  casting_time: 0,
  high_level: "Increment the die size 1 step every 5 levels (d6 » d8 » d10 » d12).",
  upcast: nil
)
