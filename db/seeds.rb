# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end


### RULES CANON (spec 02) - expanded canon slice: 11 classes, 24 ancestries, 24 backgrounds ###
stat_names = {
  "STR" => "strength",
  "DEX" => "dexterity",
  "INT" => "intelligence",
  "WIL" => "will"
}.freeze

seed_character_class = lambda do |name:, key_stats:, hit_die:, starting_hp:, save_bonus:, save_penalty:|
  key_stat_one, key_stat_two = key_stats.map { |stat| stat_names.fetch(stat) }
  save_bonus_stat = stat_names.fetch(save_bonus)
  save_penalty_stat = stat_names.fetch(save_penalty)

  character_class = CharacterClass.find_or_create_by!(name: name) do |c|
    c.key_stat_one = key_stat_one
    c.key_stat_two = key_stat_two
    c.hit_die = hit_die
    c.starting_hp = starting_hp
    c.save_bonus_stat = save_bonus_stat
    c.save_penalty_stat = save_penalty_stat
  end

  character_class.update!(
    key_stat_one: key_stat_one,
    key_stat_two: key_stat_two,
    hit_die: hit_die,
    starting_hp: starting_hp,
    save_bonus_stat: save_bonus_stat,
    save_penalty_stat: save_penalty_stat
  )
end

seed_ancestry = lambda do |name:, size:, trait_summary:, modifiers: {}|
  ancestry = Ancestry.find_or_create_by!(name: name) do |a|
    a.size = size
    a.trait_summary = trait_summary
  end

  ancestry.update!(
    {
      size: size,
      trait_summary: trait_summary,
      speed_modifier: 0,
      initiative_modifier: 0,
      all_skills_bonus: 0,
      max_hit_dice_modifier: 0,
      max_wounds_modifier: 0,
      armor_modifier: 0
    }.merge(modifiers)
  )
end

seed_background = lambda do |name:, description:, prerequisite_stat: nil, prerequisite_max: nil|
  background = Background.find_or_create_by!(name: name) do |b|
    b.description = description
    b.prerequisite_stat = prerequisite_stat
    b.prerequisite_max = prerequisite_max
  end

  background.update!(
    description: description,
    prerequisite_stat: prerequisite_stat,
    prerequisite_max: prerequisite_max
  )
end

[
  {
    name: "Berserker",
    key_stats: %w[STR DEX],
    hit_die: "1d12",
    starting_hp: 20,
    save_bonus: "STR",
    save_penalty: "INT"
  },
  {
    name: "The Cheat",
    key_stats: %w[DEX INT],
    hit_die: "1d6",
    starting_hp: 10,
    save_bonus: "DEX",
    save_penalty: "WIL"
  },
  {
    name: "Commander",
    key_stats: %w[STR INT],
    hit_die: "1d10",
    starting_hp: 17,
    save_bonus: "STR",
    save_penalty: "DEX"
  },
  {
    name: "Hunter",
    key_stats: %w[DEX WIL],
    hit_die: "1d8",
    starting_hp: 13,
    save_bonus: "DEX",
    save_penalty: "INT"
  },
  {
    name: "Mage",
    key_stats: %w[INT WIL],
    hit_die: "1d6",
    starting_hp: 10,
    save_bonus: "INT",
    save_penalty: "STR"
  },
  {
    name: "Oathsworn",
    key_stats: %w[STR WIL],
    hit_die: "1d10",
    starting_hp: 17,
    save_bonus: "STR",
    save_penalty: "DEX"
  },
  {
    name: "Shadowmancer",
    key_stats: %w[INT DEX],
    hit_die: "1d8",
    starting_hp: 13,
    save_bonus: "INT",
    save_penalty: "WIL"
  },
  {
    name: "Shepherd",
    key_stats: %w[WIL STR],
    hit_die: "1d10",
    starting_hp: 17,
    save_bonus: "WIL",
    save_penalty: "DEX"
  },
  {
    name: "Songweaver",
    key_stats: %w[WIL INT],
    hit_die: "1d8",
    starting_hp: 13,
    save_bonus: "WIL",
    save_penalty: "STR"
  },
  {
    name: "Stormshifter",
    key_stats: %w[WIL DEX],
    hit_die: "1d8",
    starting_hp: 13,
    save_bonus: "WIL",
    save_penalty: "STR"
  },
  {
    name: "Zephyr",
    key_stats: %w[DEX STR],
    hit_die: "1d8",
    starting_hp: 13,
    save_bonus: "DEX",
    save_penalty: "INT"
  }
].each do |attributes|
  seed_character_class.call(**attributes)
end

[
  {
    name: "Human",
    size: "Medium",
    trait_summary: "Versatile people with +1 to every skill and +1 Initiative.",
    modifiers: { all_skills_bonus: 1, initiative_modifier: 1 }
  },
  {
    name: "Dwarf",
    size: "Medium",
    trait_summary: "Sturdy folk with +2 max Hit Dice, +1 max Wounds, and -1 Speed.",
    modifiers: { max_hit_dice_modifier: 2, max_wounds_modifier: 1, speed_modifier: -1 }
  },
  {
    name: "Elf",
    size: "Medium",
    trait_summary: "Quick and graceful, acting with Initiative advantage and +1 Speed.",
    modifiers: { speed_modifier: 1 }
  },
  {
    name: "Halfling",
    size: "Small",
    trait_summary: "Small and lucky, with +1 Stealth and one failed save reroll per Safe Rest."
  },
  {
    name: "Gnome",
    size: "Small",
    trait_summary: "Cheerful tinkerers who let an ally reroll one die before reset, but move 1 slower.",
    modifiers: { speed_modifier: -1 }
  },
  {
    name: "Bunbun",
    size: "Small",
    trait_summary: "Springy fighters who can make a free full-speed hop after Interpose or Defend once per encounter."
  },
  {
    name: "Dragonborn",
    size: "Medium",
    trait_summary: "+1 Armor and a once-per-rest or per-Wound burst of bonus damage split among targets.",
    modifiers: { armor_modifier: 1 }
  },
  {
    name: "Fiendkin",
    size: "Medium",
    trait_summary: "Infernal resilience turns one neutral save into an advantaged one."
  },
  {
    name: "Goblin",
    size: "Small",
    trait_summary: "Can skitter 2 spaces for free after being targeted by an attack or harmful effect once."
  },
  {
    name: "Kobold",
    size: "Small",
    trait_summary: "Can force one enemy reroll per encounter and shine with friendlies and dragon lore."
  },
  {
    name: "Orc",
    size: "Medium",
    trait_summary: "Once per Safe Rest, dropping to 0 HP can leave you at HP equal to level, with +1 Might."
  },
  {
    name: "Birdfolk",
    size: "Small/Medium",
    trait_summary: "Can fly in light armor, but crits against them are harsher and forced movement carries farther."
  },
  {
    name: "Celestial",
    size: "Medium",
    trait_summary: "Radiant poise turns one disadvantaged save into a neutral one."
  },
  {
    name: "Changeling",
    size: "Medium",
    trait_summary: "Gets 2 shifting skill points and can wear another ancestry's appearance once per day."
  },
  {
    name: "Crystalborn",
    size: "Medium",
    trait_summary: "Once per encounter, Defend can grant KEY armor and reflect KEY damage."
  },
  {
    name: "Dryad/Shroomling",
    size: "Small/Medium",
    trait_summary: "Taking a Wound dazes adjacent enemies with spores or pollen."
  },
  {
    name: "Half-Giant",
    size: "Large",
    trait_summary: "Can force one critical hit reroll per encounter and gains +2 Might."
  },
  {
    name: "Minotaur/Beastfolk",
    size: "Medium",
    trait_summary: "After moving 4 spaces, can push a creature in the way once each turn."
  },
  {
    name: "Oozeling/Construct",
    size: "Small/Medium",
    trait_summary: "Hit Die size increases one step, Hit Dice heal for max, and magic healing drops to minimum."
  },
  {
    name: "Planarbeing",
    size: "Medium",
    trait_summary: "Can take 1 Wound on Defend to phase out and ignore damage, but has 2 fewer max Wounds.",
    modifiers: { max_wounds_modifier: -2 }
  },
  {
    name: "Ratfolk",
    size: "Small",
    trait_summary: "Gain +2 Armor if they moved on the previous turn."
  },
  {
    name: "Stoatling",
    size: "Small",
    trait_summary: "Single-target attacks against larger foes add extra d6s by size difference, and bigger foes do the same back."
  },
  {
    name: "Turtlefolk",
    size: "Small/Medium",
    trait_summary: "Carry heavy natural protection with +4 Armor at the cost of 2 Speed.",
    modifiers: { armor_modifier: 4, speed_modifier: -2 }
  },
  {
    name: "Wyrdling",
    size: "Small",
    trait_summary: "Once per encounter, a nearby willing tiered spellcaster can roll on the Chaos Table."
  }
].each do |attributes|
  seed_ancestry.call(**attributes)
end

[
  {
    name: "Tradesman/Artisan",
    description: "You spent years building practical skills with your hands before adventuring."
  },
  {
    name: "So Dumb I'm Smart Sometimes",
    description: "You fail upward often enough that people eventually stop calling it luck.",
    prerequisite_stat: "intelligence",
    prerequisite_max: 0
  },
  {
    name: "Wily Underdog",
    description: "You survive by staying scrappy, underestimated, and harder to pin down than expected.",
    prerequisite_stat: "strength",
    prerequisite_max: 0
  },
  {
    name: "Bumblewise",
    description: "You second-guess yourself often, but strange insight still finds you at the right moment.",
    prerequisite_stat: "will",
    prerequisite_max: 0
  },
  {
    name: "Accidental Acrobat",
    description: "You never meant to become nimble; life just kept throwing you into awkward landings.",
    prerequisite_stat: "dexterity",
    prerequisite_max: 0
  },
  {
    name: "Back Out of Retirement",
    description: "You were supposed to be done with danger, but experience pulled you back into the fray."
  },
  {
    name: "Devoted Protector",
    description: "You define yourself by shielding others, especially the people under your care."
  },
  {
    name: "Academy Dropout",
    description: "You left formal study behind and learned to improvise in the field."
  },
  {
    name: "Made a BAD Choice",
    description: "A reckless past decision still buys you trouble, debt, or enemies."
  },
  {
    name: "Haunted Past",
    description: "Old losses and lingering memories keep following you into every new place."
  },
  {
    name: "Ear to the Ground",
    description: "You have a knack for catching rumors before most people hear them."
  },
  {
    name: "What? I've Been Around",
    description: "You've wandered enough places to know someone useful almost anywhere."
  },
  {
    name: "Acrobat",
    description: "Years of tumbling, balance, and risky stunts made movement second nature."
  },
  {
    name: "Wild One",
    description: "You feel more at ease in untamed places than in polite company."
  },
  {
    name: "Fey Touched",
    description: "Something otherworldly brushed your life and left a strange mark on you."
  },
  {
    name: "Survivalist",
    description: "You know how to keep yourself fed, moving, and alive when comfort disappears."
  },
  {
    name: "Home at Sea",
    description: "Ships, tides, and waterfront life feel more natural than dry land."
  },
  {
    name: "At Home Underground",
    description: "Caves, tunnels, and stone corridors feel safer than open skies."
  },
  {
    name: "Raised by Goblins",
    description: "Goblin habits and hard lessons shaped how you talk, think, and stay alive."
  },
  {
    name: "History Buff",
    description: "You collect old stories, lineages, and forgotten details for their own sake."
  },
  {
    name: "(Former) Con Artist",
    description: "You once lived by lies and charm, and those habits never fully left."
  },
  {
    name: "(Secretly) Undead",
    description: "You hide a deeply unnatural truth behind a mostly normal face."
  },
  {
    name: "Taste for the Finer Things",
    description: "You notice quality quickly and prefer comfort, polish, and expensive details."
  },
  {
    name: "Fearless",
    description: "You meet danger head-on and hate showing hesitation."
  }
].each do |attributes|
  seed_background.call(**attributes)
end

### CHARACTERS ### (demo data predating rules canon; find_or_create_by! keeps db:seed reruns idempotent)
Character.find_or_create_by!(
  name: "Gorn",
  race: "Orc",
  nimble_class: "Zephyr",
  level: 5,
  legacy_background_text: "Angry",
  description: "Gorn is a fierce orc Zephyr, known for his swift movements and relentless aggression. His imposing presence and quick temper make him a formidable opponent on the battlefield.",
  languages: "Common, Orcish"
)

Character.find_or_create_by!(
  name: 'Luna Banana-Hammock',
  race: "Birdfolk",
  nimble_class: "Stormweaver",
  level: 10,
  legacy_background_text: "Inspirational leader",
  description: "Luna is the lone survivor of an ancient birdfolk civilization, carrying the wisdom and sorrow of her lost people. Her resilience and leadership inspire those around her, and her mastery of storm magic reflects the enduring spirit of her heritage.",
  languages: "Common, Bird, Elvish"
)

Character.find_or_create_by!(
  name: "David Andersen",
  race: "Human",
  nimble_class: "Commander (Spellblade)",
  level: 4,
  legacy_background_text: "Fearless",
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
