require "test_helper"

class CharacterTest < ActiveSupport::TestCase
  # S-02:AC-1 S-05:AC-1 S-09:AC-3
  test "starting equipment choice is limited to source-defined options and gold cannot be negative" do
    character = Character.new(starting_equipment_choice: "free_legendary_gear", current_gold: -1)

    assert_not character.valid?
    assert_includes character.errors.attribute_names, :starting_equipment_choice
    assert_includes character.errors.attribute_names, :current_gold
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-1 S-05:AC-2 S-09:AC-3
  test "a starting-gold choice scales with level and coin weight counts toward inventory" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    mage = Character.create!(
      name: "Well-funded Mage",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced",
      starting_equipment_choice: "starting_gold"
    )

    assert_equal 150, mage.current_gold
    assert_equal "150 gp", mage.starting_equipment
    assert_equal 1, mage.gold_inventory_slots
    assert_equal 1, mage.inventory_slots_used
    assert_equal "starting_gold", mage.snapshot_payload.fetch("character").fetch("starting_equipment_choice")
    assert_equal 150, mage.snapshot_payload.fetch("character").fetch("current_gold")

    mage.update!(current_gold: 501)
    assert_equal 2, mage.inventory_slots_used

    mage.update!(level: 4)
    assert_equal 200, mage.current_gold
    mage.update!(current_gold: 75)
    mage.update!(name: "Spent Mage")
    assert_equal 75, mage.current_gold
  end

  # S-02:AC-1 S-05:AC-1 S-09:AC-3
  test "class-gear starts do not grant the alternative starting-gold allowance" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    mage = Character.create!(
      name: "Equipped Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )

    assert_equal "class_gear", mage.starting_equipment_choice
    assert_includes mage.starting_equipment, "Staff"
    assert_equal 0, mage.current_gold
    assert_equal 0, mage.gold_inventory_slots
    assert_equal 4, mage.starting_gear_inventory_slots
    assert_equal 3, mage.starting_gear_inventory_items.size
    assert_equal 4, mage.inventory_slots_used
    initial_inventory = mage.character_revisions.find_by!(event_type: "created").snapshot.fetch("inventory_items")
    assert_equal 3, initial_inventory.size
    assert initial_inventory.all? { |item| item.fetch("starting_gear") && item.fetch("source_ref").present? }
    assert_equal [ 1, 2, 1 ], initial_inventory.map { |item| item.fetch("catalog_slots") }
    assert_equal mage.armor_for + mage.derived_modifier_for(:armor_modifier), mage.trait_set.armor
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "switching a draft to starting gold removes class-gear armor but preserves unarmored features" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    mage = Character.create!(
      name: "Armor Preview Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    mage.inventory_items.create!(name: "Keepsake", slots: 1)
    class_gear_armor = mage.trait_set.armor
    assert_equal mage.armor_for + mage.derived_modifier_for(:armor_modifier), class_gear_armor
    assert_equal 5, mage.inventory_slots_used

    mage.update!(starting_equipment_choice: "starting_gold")

    assert_equal 50, mage.current_gold
    assert_equal 2, mage.inventory_slots_used
    assert_empty mage.starting_gear_inventory_items
    assert mage.inventory_items.exists?(name: "Keepsake", starting_gear: false)
    unarmored_armor = mage.stat_value("dexterity") + mage.derived_modifier_for(:armor_modifier)
    assert_equal unarmored_armor, mage.trait_set.armor

    mage.update!(starting_equipment_choice: "class_gear")
    assert_equal 0, mage.current_gold
    assert_equal 5, mage.inventory_slots_used
    assert_equal class_gear_armor, mage.trait_set.armor
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "starting class gear contributes to inventory use for every catalog class" do
    Rails.application.load_seed unless CharacterClass.count >= 11
    expected_slots = {
      "Berserker" => 4, "The Cheat" => 6, "Commander" => 3, "Hunter" => 5,
      "Mage" => 4, "Oathsworn" => 4, "Shadowmancer" => 3, "Shepherd" => 4,
      "Songweaver" => 4, "Stormshifter" => 4, "Zephyr" => 3
    }

    expected_slots.each do |class_name, slots|
      character = Character.create!(
        name: "#{class_name} slot test",
        character_class: CharacterClass.find_by!(name: class_name),
        starting_equipment_choice: "class_gear"
      )

      assert_equal slots, character.starting_gear_inventory_slots, "#{class_name} kit slots"
      assert_equal slots, character.inventory_slots_used, "#{class_name} total slots before carried items"
      assert_equal Rules::NimbleCatalog.starting_gear_inventory_items(class_name).size, character.starting_gear_inventory_items.size
    end
  end

  # S-02:AC-1 S-02:AC-2 S-03:AC-3 S-05:AC-2 S-09:AC-3
  test "changing a draft class replaces only starting kit items" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    mage = Character.create!(name: "Class Change Draft", character_class: CharacterClass.find_by!(name: "Mage"))
    mage.inventory_items.create!(name: "Found key", slots: 1)

    mage.update!(character_class: CharacterClass.find_by!(name: "Berserker"))

    assert_equal [ "Battleaxe", "Rations (meat)", "Rope (50 ft.)" ], mage.starting_gear_inventory_items.order(:id).pluck(:name)
    assert mage.inventory_items.exists?(name: "Found key", starting_gear: false)
    assert_not mage.inventory_items.exists?(name: "Staff")
    assert_equal 5, mage.inventory_slots_used
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "starting bucklers add Armor for Oathsworn and Shepherd but not on gold starts" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Oathsworn")

    %w[Oathsworn Shepherd].each do |class_name|
      character_class = CharacterClass.find_by!(name: class_name)
      character = Character.new(character_class:, starting_equipment_choice: "class_gear")

      assert_includes character_class.starting_gear, "Wooden Buckler"
      assert_equal "Core Rules 2.0.1, p. 33", character_class.armor_rules.fetch("source_ref")
      assert_equal 10, character.armor_for({ "dexterity" => 3 })

      character.starting_equipment_choice = "starting_gold"
      assert_equal 3, character.armor_for({ "dexterity" => 3 })
    end

    commander = CharacterClass.find_by!(name: "Commander")
    assert_nil commander.armor_rules["shield_bonus"]
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "Zephyr unarmored Armor uses DEX plus STR and doubles at level 13" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Zephyr")
    zephyr = Character.new(
      character_class: CharacterClass.find_by!(name: "Zephyr"),
      starting_equipment_choice: "starting_gold"
    )
    stats = { "dexterity" => 2, "strength" => 1 }

    assert_equal 3, zephyr.armor_for(stats, level: 1)
    assert_equal 6, zephyr.armor_for(stats, level: 13)
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "class-gear and gold-start Armor match source formulas for all eleven classes" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Zephyr")
    expected_armor = {
      "Berserker" => [ 3, 3 ],
      "The Cheat" => [ 6, 3 ],
      "Commander" => [ 8, 3 ],
      "Hunter" => [ 6, 3 ],
      "Mage" => [ 5, 3 ],
      "Oathsworn" => [ 10, 3 ],
      "Shadowmancer" => [ 5, 3 ],
      "Shepherd" => [ 10, 3 ],
      "Songweaver" => [ 5, 3 ],
      "Stormshifter" => [ 6, 3 ],
      "Zephyr" => [ 4, 4 ]
    }
    stats = { "strength" => 1, "dexterity" => 3 }

    expected_armor.each do |class_name, (class_gear_armor, gold_start_armor)|
      character = Character.new(
        character_class: CharacterClass.find_by!(name: class_name),
        starting_equipment_choice: "class_gear"
      )
      assert_equal class_gear_armor, character.armor_for(stats), "#{class_name} class gear should match its source Armor"

      character.starting_equipment_choice = "starting_gold"
      assert_equal gold_start_armor, character.armor_for(stats), "#{class_name} gold start should use its unarmored Armor"
    end
  end

  # S-04:AC-1 S-05:AC-5
  test "unfinished drafts may leave the stat array blank but reject unknown arrays" do
    draft = Character.new(name: "Work in progress", status: "draft", stat_array: "")

    assert draft.valid?
    assert_empty draft.errors[:stat_array]

    draft.stat_array = "invented"

    assert_not draft.valid?
    assert_includes draft.errors[:stat_array], "is not included in the list"
  end

  test "defaults remain unchanged without an ancestry" do
    character_class = CharacterClass.create!(
      name: "Warrior",
      key_stat_one: "strength",
      key_stat_two: "dexterity",
      hit_die: "1d8",
      starting_hp: 12,
      save_bonus_stat: "strength",
      save_penalty_stat: "intelligence"
    )

    character = Character.create!(name: "Baseline", character_class: character_class)

    assert_equal 0, character.skill_set.arcana
    assert_equal 0, character.skill_set.stealth
    assert_equal 0, character.skill_set.perception
    assert_equal 0, character.trait_set.initiative
    assert_equal 6, character.trait_set.speed
    assert_equal 10, character.trait_set.inventory_slots
    assert_equal 1, character.trait_set.current_hit_dice
    assert_equal 1, character.trait_set.max_hit_dice
    assert_equal 0, character.trait_set.armor
    assert_equal 0, character.trait_set.current_wounds
    assert_equal 6, character.trait_set.max_wounds
  end

  test "ancestry modifiers apply to derived defaults" do
    character_class = CharacterClass.create!(
      name: "Scholar",
      key_stat_one: "intelligence",
      key_stat_two: "will",
      hit_die: "1d10",
      starting_hp: 9,
      save_bonus_stat: "will",
      save_penalty_stat: "strength"
    )
    ancestry = Ancestry.create!(
      name: "Testing Ancestry",
      size: "Medium",
      trait_summary: "Applies flat modifiers.",
      speed_modifier: -1,
      initiative_modifier: 2,
      all_skills_bonus: 3,
      max_hit_dice_modifier: 2,
      max_wounds_modifier: 1,
      armor_modifier: 4
    )

    character = Character.create!(
      name: "Modified",
      character_class: character_class,
      ancestry: ancestry
    )

    assert_equal 3, character.skill_set.arcana
    assert_equal 3, character.skill_set.insight
    assert_equal 3, character.skill_set.examination
    assert_equal 3, character.skill_set.finesse
    assert_equal 3, character.skill_set.might
    assert_equal 3, character.skill_set.lore
    assert_equal 3, character.skill_set.influence
    assert_equal 3, character.skill_set.naturecraft
    assert_equal 3, character.skill_set.stealth
    assert_equal 3, character.skill_set.perception

    assert_equal 2, character.trait_set.initiative
    assert_equal 5, character.trait_set.speed
    assert_equal 10, character.trait_set.inventory_slots
    assert_equal 3, character.trait_set.current_hit_dice
    assert_equal 3, character.trait_set.max_hit_dice
    assert_equal 4, character.trait_set.armor
    assert_equal 0, character.trait_set.current_wounds
    assert_equal 7, character.trait_set.max_wounds
    assert_equal "1d10", character.trait_set.hit_die
    assert_equal 9, character.trait_set.current_hp
    assert_equal 9, character.trait_set.max_hp
  end

  test "per-skill ancestry bonuses are part of the governing skill baseline" do
    character_class = CharacterClass.create!(
      name: "Skill Bonus Class",
      key_stat_one: "strength",
      key_stat_two: "dexterity",
      hit_die: "1d8",
      starting_hp: 12
    )
    ancestry = Ancestry.create!(name: "Skill Bonus Ancestry", size: "Small", skill_modifiers: { stealth: 1 })
    character = Character.create!(name: "Skill Bonus Hero", character_class: character_class, ancestry: ancestry, stat_array: "balanced")

    assert_equal character.stat_value("dexterity") + 1, character.skill_initial_value("stealth")
    assert_equal character.skill_initial_value("stealth"), character.skill_value("stealth")
  end

  test "changing background recalculates origin-derived values and language grants" do
    character_class = CharacterClass.create!(
      name: "Background Change Class",
      key_stat_one: "intelligence",
      key_stat_two: "will",
      hit_die: "1d6",
      starting_hp: 10
    )
    ancestry = Ancestry.create!(name: "Background Change Ancestry", size: "Medium", language_grants: [ "Dwarvish" ])
    original_background = Background.create!(name: "Original Background", description: "The first story.")
    replacement_background = Background.create!(
      name: "Structured Background",
      description: "The second story.",
      initiative_modifier: 1,
      armor_modifier: -1,
      max_hit_dice_modifier: 1,
      skill_modifiers: { naturecraft: 1 },
      language_grants: [ "Goblin" ]
    )
    character = Character.create!(
      name: "Background Change Hero",
      character_class: character_class,
      ancestry: ancestry,
      background: original_background,
      stat_array: "balanced"
    )

    character.update!(background: replacement_background)
    character.reload

    assert_equal character.stat_value("dexterity") + 1, character.trait_set.initiative
    assert_equal character.stat_value("dexterity") - 1, character.trait_set.armor
    assert_equal 2, character.trait_set.max_hit_dice
    assert_equal character.stat_value("will") + 1, character.skill_value("naturecraft")
    assert_includes character.languages, "Dwarvish"
    assert_includes character.languages, "Goblin"
  end

  # S-05:AC-2 S-06:AC-6
  test "canonical edits recalculate affected values without wiping tracker state" do
    original_class = CharacterClass.create!(
      name: "Original Class",
      key_stat_one: "strength",
      key_stat_two: "dexterity",
      hit_die: "1d10",
      starting_hp: 12,
      save_bonus_stat: "strength",
      save_penalty_stat: "intelligence"
    )
    replacement_class = CharacterClass.create!(
      name: "Replacement Class",
      key_stat_one: "intelligence",
      key_stat_two: "will",
      hit_die: "1d6",
      starting_hp: 20,
      save_bonus_stat: "intelligence",
      save_penalty_stat: "strength"
    )
    original_ancestry = Ancestry.create!(name: "Original Ancestry", size: "Medium")
    replacement_ancestry = Ancestry.create!(
      name: "Replacement Ancestry",
      size: "Small",
      all_skills_bonus: 2,
      speed_modifier: 2,
      max_wounds_modifier: 1
    )
    character = Character.create!(
      name: "Editable Hero",
      level: 1,
      character_class: original_class,
      ancestry: original_ancestry,
      stat_array: "balanced"
    )
    character.skill_set.update!(might: 6)
    character.trait_set.update!(current_hp: 5, current_wounds: 2, current_actions: 1, temp_hp: 3)

    character.update!(character_class: replacement_class, ancestry: replacement_ancestry, stat_array: "balanced")
    character.reload

    assert_equal 2, character.stat_set.intelligence
    assert_equal 1, character.stat_set.will
    assert_equal 4, character.skill_set.arcana
    assert_equal 6, character.skill_set.might
    assert_equal 20, character.trait_set.max_hp
    assert_equal 5, character.trait_set.current_hp
    assert_equal 7, character.trait_set.max_wounds
    assert_equal 2, character.trait_set.current_wounds
    assert_equal 1, character.trait_set.current_actions
    assert_equal 3, character.trait_set.temp_hp
    assert_equal 8, character.trait_set.speed
  end

  test "catalog-backed casters derive save DC, mana, and starting gear" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    character = Character.create!(
      name: "Catalog Mage",
      level: 2,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )

    assert_equal 12, character.trait_set.save_dc
    assert_equal 8, character.trait_set.max_mana
    assert_equal 8, character.trait_set.current_mana
    assert_equal "Mana", character.trait_set.resource_name
    assert_equal 2, character.trait_set.initiative
    assert_equal 1, character.trait_set.armor
    assert_includes character.starting_equipment, "Staff"
    assert_includes character.inventory, "Adventurer's Garb"
    assert_includes character.character_class.armor_proficiencies, "cloth"

    character.trait_set.update!(current_mana: 3)
    character.update!(stat_array: "min_max")

    assert_equal 11, character.trait_set.max_mana
    assert_equal 3, character.trait_set.current_mana

    zephyr = Character.create!(
      name: "Catalog Zephyr",
      character_class: CharacterClass.find_by!(name: "Zephyr"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )

    assert_equal 2, zephyr.trait_set.armor
  end

  test "creation preserves a freely placed stat array and derives from that placement" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Unusual Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.create!(name: "Unusual Mage Background", description: "No modifiers."),
      stat_array: "balanced",
      stat_assignments: { strength: 0, dexterity: 1, intelligence: 1, will: 2 }
    )

    assert_equal({ "strength" => 0, "dexterity" => 1, "intelligence" => 1, "will" => 2 }, character.stat_assignment_values)
    assert_equal 1, character.stat_set.intelligence
    assert_equal 2, character.stat_set.will
    assert_equal 12, character.trait_set.save_dc
    assert_equal 3, character.trait_set.armor
    assert_equal 2, character.trait_set.initiative
    assert_equal 10, character.trait_set.inventory_slots
  end

  test "creation rejects a stat placement that does not use the selected array" do
    Rails.application.load_seed
    character = Character.new(
      name: "Invalid Placement",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced",
      stat_assignments: { strength: 2, dexterity: 2, intelligence: 1, will: 0 }
    )

    assert_not character.valid?
    assert_includes character.errors[:stat_assignments], "must use each value from the selected stat array exactly once"
    assert_includes character.creation_issues.map { |issue| issue.fetch(:message) }, "Place each value from the Balanced array exactly once."
  end

  test "invalid stat arrays remain validation errors when assignments are present" do
    Rails.application.load_seed
    character = Character.new(
      name: "Unknown Array",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "invented",
      stat_assignments: { strength: 0, dexterity: 1, intelligence: 2, will: 3 }
    )

    assert_not character.valid?
    assert_includes character.errors[:stat_array], "is not included in the list"
  end

  test "class progression and subclass milestones come from the source catalog" do
    Rails.application.load_seed
    berserker = CharacterClass.find_by!(name: "Berserker")

    assert_equal [ "Intensifying Fury", "One with the Ancients" ], berserker.features_for(2)
    assert_includes berserker.features_for(4), "Savage Arsenal"
    assert_equal [ "Stone's Resilience", "Mountainous Tenacity" ], berserker.subclass_features_for("Path of the Mountainheart", 3)
    assert_equal [ "Titan's Fury" ], berserker.subclass_features_for("Path of the Mountainheart", 11)

    character = Character.new(
      name: "Progression Hero",
      level: 11,
      character_class: berserker,
      subclass_name: "Path of the Mountainheart"
    )
    class_features = character.progression_features_through.map { |feature| feature.values_at(:level, :name) }
    subclass_features = character.subclass_progression_features_through.map { |feature| feature.values_at(:level, :name) }

    assert_includes class_features, [ 2, "Intensifying Fury" ]
    assert_includes subclass_features, [ 11, "Titan's Fury" ]
    assert_equal({ "bonus" => "strength", "penalty" => "intelligence" }, character.snapshot_payload.fetch("rules").fetch("saves"))

    Rules::NimbleCatalog.classes.each_key do |class_name|
      character_class = CharacterClass.find_by!(name: class_name)
      assert character_class.features_for(1).any?, "#{character_class.name} is missing its level-one progression"
      character_class.subclass_options.each do |subclass|
        assert character_class.subclass_features_for(subclass, 3).any?, "#{character_class.name} / #{subclass} is missing its level-three progression"
      end
    end
  end

  test "feature-choice pools preserve source counts, options, and prerequisites" do
    Rails.application.load_seed

    hunter = CharacterClass.find_by!(name: "Hunter")
    hunter_pool = hunter.feature_choice_pools_for(2).first
    assert_equal "Thrill of the Hunt", hunter_pool.fetch("name")
    assert_equal 2, hunter_pool.fetch("count")
    assert_includes hunter_pool.fetch("options"), "Wild Instinct"
    assert_equal 1, hunter.feature_choice_pools_for(4).first.fetch("count")

    mage = CharacterClass.find_by!(name: "Mage")
    assert_equal 2, mage.feature_choice_pools_for(4).first.fetch("count")
    assert_includes mage.feature_choice_pools_for(4).first.fetch("options"), "Stretch Time"

    songweaver = CharacterClass.find_by!(name: "Songweaver")
    people_pool = songweaver.feature_choice_pools_for(5).first
    assert_equal "A People Person", people_pool.fetch("name")
    assert_equal 2, people_pool.fetch("count")
    assert_includes people_pool.fetch("options"), "Stompy"

    cheat = CharacterClass.find_by!(name: "The Cheat")
    requirements = cheat.feature_choice_pools_for(4).first.fetch("requires")
    assert_equal [ "Sunder Armor (Medium)" ], requirements.fetch("Sunder Armor (Heavy)")

    commander = CharacterClass.find_by!(name: "Commander")
    assert_equal 5, commander.feature_choice_pools_for(2).first.fetch("options").length
    assert_not_includes commander.feature_choice_pools_for(2).first.fetch("options"), "Commanding Presence"
    assert_includes commander.feature_choice_pools_for(4).first.fetch("options"), "Commanding Presence"

    berserker = CharacterClass.find_by!(name: "Berserker")
    assert_equal 1, berserker.feature_choice_pools_for(4).first.fetch("count")
    assert_includes berserker.feature_choice_pools_for(4).first.fetch("options"), "Deathless Rage"
  end

  test "recorded feature choices appear in the progression snapshot" do
    Rails.application.load_seed
    character = Character.new(
      name: "Choice Snapshot Hero",
      level: 4,
      character_class: CharacterClass.find_by!(name: "Berserker"),
      feature_choices: { "Savage Arsenal" => [ "Death Blow" ] }
    )

    entry = character.feature_choice_entries_through.first
    assert_equal 4, entry.fetch(:level)
    assert_equal [ "Death Blow" ], entry.fetch(:selected)
    assert_equal [ "Death Blow" ], character.snapshot_payload.fetch("progression").fetch("feature_choices").first.fetch(:selected)
  end

  test "feature-choice history stays attached to the level where it was selected" do
    Rails.application.load_seed
    character = Character.new(
      name: "Choice History Hero",
      level: 4,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      feature_choices: {
        "Thrill of the Hunt" => {
          "2" => [ "Fleet Feet", "Wild Instinct" ],
          "4" => [ "Decoy" ]
        }
      }
    )

    entries = character.feature_choice_entries_through
    assert_equal [ 2, 4 ], entries.map { |entry| entry.fetch(:level) }
    assert_equal [ "Fleet Feet", "Wild Instinct" ], entries.first.fetch(:selected)
    assert_equal [ "Decoy" ], entries.last.fetch(:selected)
  end

  test "source-defined utility spell auto-grants become available at their milestone" do
    Rails.application.load_seed
    shepherd = Character.new(
      name: "Utility Auto Grant Hero",
      level: 11,
      character_class: CharacterClass.find_by!(name: "Shepherd"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard"
    )

    assert_includes shepherd.utility_spell_names, "Light"
    assert_includes shepherd.utility_spell_names, "Gravecraft"
    assert shepherd.granted_utility_spells.exists?(name: "False Face")
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-1 S-05:AC-2 S-09:AC-1
  test "Academy Dropout requires and grants one source-defined Utility Spell" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Academy Dropout Hero",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Academy Dropout"),
      stat_array: "standard",
      skill_set_attributes: { arcana: 7 }
    )
    missing_choice = character.creation_issues.find { |issue| issue.fetch(:message).include?("Academy Dropout requires") }

    assert_equal "Core Rules 2.0.1, p. 28", missing_choice.fetch(:source_ref)
    assert_includes character.spell_choice_pools_for(1).first.fetch("options"), "Wind Whisper"

    character.update!(spell_choices: { "Academy Dropout" => { "1" => [ "Snowblind" ] } })
    invalid_choice = character.creation_issues.find { |issue| issue.fetch(:message).include?("not a Utility Spell option") }
    assert_equal "Core Rules 2.0.1, p. 28", invalid_choice.fetch(:source_ref)
    assert_not character.legal_for_creation?

    character.update!(spell_choices: { "Academy Dropout" => { "1" => [ "Wind Whisper" ] } })
    assert character.legal_for_creation?, character.creation_issues.map { |issue| issue.fetch(:message) }.join(" | ")
    character.finalize_creation!

    character.reload
    assert_includes character.utility_spell_names, "Wind Whisper"
    assert_includes character.spells.pluck(:name), "Wind Whisper"
    assert_includes character.available_spells.map(&:name), "Wind Whisper"
    choice = character.spell_choice_entries_through.first
    assert_equal [ "Wind Whisper" ], choice.fetch(:selected)
    assert_equal "Core Rules 2.0.1, p. 28", choice.fetch(:source_ref)
  end

  test "resource tracks follow class unlocks, maxima, and encounter starting states" do
    Rails.application.load_seed
    ancestry = Ancestry.find_by!(name: "Human")
    background = Background.find_by!(name: "Fearless")

    berserker = Character.create!(character_class: CharacterClass.find_by!(name: "Berserker"), ancestry:, background:, stat_array: "standard")
    fury = berserker.trait_set.resource_tracks.first
    assert_equal "fury_dice", fury.fetch("key")
    assert_equal 2, fury.fetch("max")
    assert_equal 0, fury.fetch("current")
    assert_equal 0, fury.fetch("initial_current")
    assert_equal "d4", fury.fetch("die")

    oathsworn = Character.create!(level: 1, character_class: CharacterClass.find_by!(name: "Oathsworn"), ancestry:, background:, stat_array: "standard")
    judgment = oathsworn.trait_set.resource_tracks.find { |track| track.fetch("key") == "judgment_dice" }
    assert_equal 2, judgment.fetch("max")
    assert_equal 0, judgment.fetch("current")
    assert_equal "2d6", judgment.fetch("die")

    oathsworn_level_two = Character.create!(level: 2, character_class: CharacterClass.find_by!(name: "Oathsworn"), ancestry:, background:, stat_array: "standard")
    tracks = oathsworn_level_two.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal 4, tracks.fetch("mana").fetch("max")
    assert_equal 4, tracks.fetch("mana").fetch("current")
    assert_equal 10, tracks.fetch("lay_on_hands").fetch("max")
    assert_equal 0, tracks.fetch("judgment_dice").fetch("current")

    hunter = Character.create!(level: 2, character_class: CharacterClass.find_by!(name: "Hunter"), ancestry:, background:, stat_array: "standard")
    thrill = hunter.trait_set.resource_tracks.first
    assert_equal "thrill_of_the_hunt", thrill.fetch("key")
    assert_nil thrill["max"]
    assert_equal 0, thrill.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "limited-use ancestry abilities become source-backed game resource tracks" do
    Rails.application.load_seed
    character_class = CharacterClass.find_by!(name: "Mage")
    background = Background.find_by!(name: "Fearless")
    expected = {
      "Halfling" => [ "ancestry_halfling_elusive", "Safe Rest", "Core Rules 2.0.1, p. 23" ],
      "Gnome" => [ "ancestry_gnome_optimistic", "Healed to max HP", "Core Rules 2.0.1, p. 23" ],
      "Bunbun" => [ "ancestry_bunbun_bunny_legs", "Encounter ends", "Core Rules 2.0.1, p. 24" ],
      "Dragonborn" => [ "ancestry_dragonborn_draconic_heritage", "Safe Rest or gain a Wound", "Core Rules 2.0.1, p. 24" ],
      "Kobold" => [ "ancestry_kobold_wily", "Encounter ends", "Core Rules 2.0.1, p. 24" ],
      "Orc" => [ "ancestry_orc_relentless", "Safe Rest", "Core Rules 2.0.1, p. 24" ],
      "Changeling" => [ "ancestry_changeling_new_place_new_face", "New day", "Core Rules 2.0.1, p. 26" ],
      "Crystalborn" => [ "ancestry_crystalborn_reflective_aura", "Encounter ends", "Core Rules 2.0.1, p. 26" ],
      "Half-Giant" => [ "ancestry_half_giant_strength_of_stone", "Encounter ends", "Core Rules 2.0.1, p. 26" ],
      "Wyrdling" => [ "ancestry_wyrdling_chaotic_surge", "Encounter ends", "Core Rules 2.0.1, p. 27" ]
    }

    expected.each do |ancestry_name, (key, reset, source_ref)|
      character = Character.create!(
        name: "#{ancestry_name} Tracker",
        character_class: character_class,
        ancestry: Ancestry.find_by!(name: ancestry_name),
        background: background,
        stat_array: "balanced"
      )
      track = character.trait_set.resource_tracks.find { |entry| entry.fetch("key") == key }

      assert_equal 1, track.fetch("max"), ancestry_name
      assert_equal 1, track.fetch("current"), ancestry_name
      assert_equal reset, track.fetch("reset"), ancestry_name
      assert_equal source_ref, track.fetch("source_ref"), ancestry_name
      assert track.fetch("source_quote").present?, ancestry_name
    end
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "Safe Rest applies recovery and source-defined resource resets" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Resting Dragonborn",
      level: 2,
      character_class: CharacterClass.find_by!(name: "Oathsworn"),
      ancestry: Ancestry.find_by!(name: "Dragonborn"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    spent_tracks = character.trait_set.resource_tracks.map { |track| track.merge("current" => 0) }
    character.trait_set.update!(
      current_hp: 2,
      current_hit_dice: 0,
      current_wounds: 2,
      temp_hp: 5,
      current_mana: 0,
      current_resource: 0,
      resource_tracks: spent_tracks
    )

    character.take_safe_rest!
    character.reload
    tracks = character.trait_set.resource_tracks.index_by { |track| track.fetch("key") }

    assert_equal character.trait_set.max_hp, character.trait_set.current_hp
    assert_equal character.trait_set.max_hit_dice, character.trait_set.current_hit_dice
    assert_equal 1, character.trait_set.current_wounds
    assert_equal 0, character.trait_set.temp_hp
    assert_equal character.trait_set.max_mana, tracks.fetch("mana").fetch("current")
    assert_equal tracks.fetch("lay_on_hands").fetch("max"), tracks.fetch("lay_on_hands").fetch("current")
    assert_equal 1, tracks.fetch("ancestry_dragonborn_draconic_heritage").fetch("current")
    assert character.character_revisions.exists?(event_type: "safe_rest", summary: "Safe Rest completed")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "Safe Rest resets encounter and healed-to-full resources but not daily uses" do
    Rails.application.load_seed
    hunter = Character.create!(
      name: "Resting Gnome",
      level: 2,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      ancestry: Ancestry.find_by!(name: "Gnome"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    spent_tracks = hunter.trait_set.resource_tracks.map do |track|
      current = track.fetch("key") == "thrill_of_the_hunt" ? 3 : 0
      track.merge("current" => current)
    end
    hunter.trait_set.update!(current_hp: 1, resource_tracks: spent_tracks)

    hunter.take_safe_rest!

    tracks = hunter.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal 0, tracks.fetch("thrill_of_the_hunt").fetch("current")
    assert_equal 1, tracks.fetch("ancestry_gnome_optimistic").fetch("current")

    changeling = Character.create!(
      name: "Resting Changeling",
      level: 2,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      ancestry: Ancestry.find_by!(name: "Changeling"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    changeling_tracks = changeling.trait_set.resource_tracks.map do |track|
      track.fetch("key") == "ancestry_changeling_new_place_new_face" ? track.merge("current" => 0) : track
    end
    changeling.trait_set.update!(resource_tracks: changeling_tracks)

    changeling.take_safe_rest!

    assert_equal 0, changeling.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "ancestry_changeling_new_place_new_face" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "Catch Breath spends rolled Hit Dice and adds STR to each result" do
    Rails.application.load_seed
    mage = Character.create!(
      name: "Breathing Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      stat_assignments: { strength: -1, dexterity: 0, intelligence: 2, will: 2 }
    )
    mage.trait_set.update!(current_hp: 2)

    result = mage.perform_field_rest!(mode: "catch_breath", hit_dice_count: "1", die_rolls: [ "6" ])

    mage.reload
    assert_equal(-1, mage.stat_value("strength"))
    assert_equal 5, result.fetch(:hp_recovered)
    assert_equal 7, mage.trait_set.current_hp
    assert_equal 0, mage.trait_set.current_hit_dice
    assert mage.character_revisions.exists?(event_type: "field_rest", summary: "Catch Breath: spent 1 Hit Die, recovered 5 HP")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "Make Camp uses maximum Hit Die results and caps healing at max HP" do
    Rails.application.load_seed
    oathsworn = Character.create!(
      name: "Camping Oathsworn",
      level: 2,
      character_class: CharacterClass.find_by!(name: "Oathsworn"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    oathsworn.trait_set.update!(current_hp: 1, current_hit_dice: 2)

    result = oathsworn.perform_field_rest!(mode: "make_camp", hit_dice_count: 2)

    oathsworn.reload
    assert_equal oathsworn.trait_set.max_hp - 1, result.fetch(:hp_recovered)
    assert_equal oathsworn.trait_set.max_hp, oathsworn.trait_set.current_hp
    assert_equal 0, oathsworn.trait_set.current_hit_dice
  end

  # S-02:AC-1 S-09:AC-1 S-09:AC-3
  test "Catch Breath resolves one Hit Die before the player chooses whether to continue" do
    Rails.application.load_seed
    oathsworn = Character.create!(
      name: "Sequential Rest Oathsworn",
      level: 2,
      character_class: CharacterClass.find_by!(name: "Oathsworn"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    original_hp = oathsworn.trait_set.current_hp
    original_hit_dice = oathsworn.trait_set.current_hit_dice

    error = assert_raises(ArgumentError) do
      oathsworn.perform_field_rest!(mode: "catch_breath", hit_dice_count: 2, die_rolls: [ "4", "5" ])
    end

    assert_includes error.message, "one Hit Die at a time"
    assert_equal original_hp, oathsworn.reload.trait_set.current_hp
    assert_equal original_hit_dice, oathsworn.trait_set.current_hit_dice
  end

  # S-02:AC-1 S-09:AC-1 S-09:AC-3
  test "Catch Breath rejects die results outside the character's Hit Die" do
    Rails.application.load_seed
    mage = Character.create!(
      name: "Invalid Breath Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    original_hp = mage.trait_set.current_hp
    original_hit_dice = mage.trait_set.current_hit_dice
    original_revisions = mage.character_revisions.count

    error = assert_raises(ArgumentError) do
      mage.perform_field_rest!(mode: "catch_breath", hit_dice_count: 1, die_rolls: [ "7" ])
    end

    assert_includes error.message, "each from 1 to 6"
    assert_equal original_hp, mage.reload.trait_set.current_hp
    assert_equal original_hit_dice, mage.trait_set.current_hit_dice
    assert_equal original_revisions, mage.character_revisions.count
  end

  test "canonical class and subclass features alter derived movement, defenses, and hit dice" do
    Rails.application.load_seed
    ancestry = Ancestry.find_by!(name: "Human")
    background = Background.find_by!(name: "Fearless")

    wild_heart = Character.create!(
      level: 15,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      subclass_name: "Wild Heart",
      ancestry:,
      background:,
      stat_array: "standard"
    )
    assert_equal 18, wild_heart.trait_set.max_hp
    assert_equal "1d10", wild_heart.trait_set.hit_die
    assert_equal 6, wild_heart.trait_set.armor
    assert_equal "1d10", wild_heart.snapshot_payload.fetch("progression").fetch("derived_effects").fetch("hit_die")

    oathbreaker = Character.create!(
      level: 3,
      character_class: CharacterClass.find_by!(name: "Oathsworn"),
      subclass_name: "Oathbreaker",
      ancestry:,
      background:,
      stat_array: "standard"
    )
    assert_equal 8, oathbreaker.trait_set.max_wounds

    zephyr = Character.create!(
      level: 13,
      character_class: CharacterClass.find_by!(name: "Zephyr"),
      ancestry:,
      background:,
      stat_array: "standard"
    )
    assert_equal 10, zephyr.trait_set.speed
    assert_equal 17, zephyr.trait_set.initiative
    assert_equal 7, zephyr.trait_set.armor
  end
end
