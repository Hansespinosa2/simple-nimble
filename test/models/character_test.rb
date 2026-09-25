require "test_helper"

class CharacterTest < ActiveSupport::TestCase
  # S-02:AC-1 S-02:AC-2 S-05:AC-1 S-05:AC-2
  test "positive INT creates explicit language slots rather than guessed languages" do
    Rails.application.load_seed
    character = Character.new(
      name: "Language Choice Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )

    assert character.valid?
    assert_equal 2, character.stat_set.intelligence
    assert_equal "Common", character.languages
    assert_includes character.language_issues_for(stat_values: { intelligence: 2 }, choices: []).first.fetch(:message), "Choose 2 more languages"

    character.language_choices = [ "Elvish", "Draconic" ]
    assert character.valid?
    assert_equal 2, character.stat_set.intelligence, "saving language choices must not reset derived stats"
    assert_equal "Common, Elvish, Draconic", character.languages
    assert_empty character.language_issues_for(stat_values: { intelligence: 2 }, choices: character.language_choices)
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-1
  test "ancestry languages unlock at INT zero but not at negative INT" do
    Rails.application.load_seed
    character = Character.new(
      name: "Dwarven Language Threshold",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Dwarf"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      stat_assignments: { strength: 2, dexterity: 0, intelligence: -1, will: 2 }
    )
    character.valid?

    assert_equal(-1, character.stat_set.intelligence)
    assert_equal [ "Common" ], character.known_language_names

    character.stat_assignments = { strength: 2, dexterity: 2, intelligence: 0, will: -1 }
    character.valid?

    assert_equal 0, character.stat_set.intelligence
    assert_includes character.known_language_names, "Dwarvish"
    assert_equal 0, character.language_choice_count
  end

  # S-02:AC-1 S-02:AC-2 S-06:AC-2
  test "published class and feature language grants are tracked without duplicating INT choices" do
    Rails.application.load_seed
    cheat = Character.new(
      name: "Cheat's Cant",
      level: 3,
      character_class: CharacterClass.find_by!(name: "The Cheat"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Draconic", "Primordial" ]
    )
    cheat.valid?
    assert_includes cheat.known_language_names, "Thieves' Cant"
    assert_equal "Heroes 2.0.1, p. 14", Rules::NimbleCatalog.class_language_rules_for("The Cheat").first.fetch("source_ref")

    shadowmancer = Character.new(
      name: "Devoted Acolyte",
      character_class: CharacterClass.find_by!(name: "Shadowmancer"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Elvish", "Goblin" ]
    )
    selections = { "Devoted Acolyte" => [ "Celestial", "Deep Speak" ] }
    feature_choices = { "Lesser Shadow Invocation" => [ "Devoted Acolyte" ] }

    assert_empty shadowmancer.language_issues_for(
      stat_values: { intelligence: 2 },
      choices: shadowmancer.language_choices,
      feature_choices:,
      feature_selections: selections,
      level: 3
    )
    known = shadowmancer.known_language_names(
      { intelligence: 2 },
      choices: shadowmancer.language_choices,
      level: 3,
      feature_choices:,
      feature_language_choices: selections
    )
    assert_equal %w[Common Elvish Goblin Celestial], known.first(4)
    assert_includes known, "Deep Speak"

    incomplete = shadowmancer.language_issues_for(
      stat_values: { intelligence: 2 },
      choices: shadowmancer.language_choices,
      feature_choices:,
      feature_selections: { "Devoted Acolyte" => [ "Celestial" ] },
      level: 3
    )
    assert_includes incomplete.map { |issue| issue.fetch(:message) }, "Choose 1 more language for Devoted Acolyte."
    assert_equal "Heroes 2.0.1, p. 46", incomplete.find { |issue| issue.fetch(:message).include?("Devoted Acolyte") }.fetch(:source_ref)
  end

  # S-02:AC-1 S-05:AC-1 S-09:AC-3
  test "starting equipment choice is limited to source-defined options and gold cannot be negative" do
    character = Character.new(starting_equipment_choice: "free_legendary_gear", current_gold: -1)

    assert_not character.valid?
    assert_includes character.errors.attribute_names, :starting_equipment_choice
    assert_includes character.errors.attribute_names, :current_gold
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Bloodied, Dying, and Wounded are derived from current HP and Wounds" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    character = Character.create!(
      name: "Condition State Hero",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    traits = character.trait_set
    max_hp = traits.max_hp

    traits.update!(current_hp: max_hp / 2 + 1, current_wounds: 0)
    assert_empty character.derived_condition_entries

    traits.update!(current_hp: max_hp / 2, current_wounds: 1)
    entries = character.derived_condition_entries
    assert_equal %w[Bloodied Wounded], entries.map { |entry| entry.fetch("name") }
    assert_equal "At half HP or less.", entries.first.fetch("source_quote")
    assert_equal "Core Rules 2.0.1, p. 11", entries.first.fetch("source_ref")

    traits.update!(current_hp: 0, current_wounds: 0)
    dying = character.derived_condition_entries.find { |entry| entry.fetch("name") == "Dying" }
    assert_equal %w[Bloodied Dying], character.derived_condition_entries.map { |entry| entry.fetch("name") }
    assert_equal 1, dying.fetch("actions_limited_to")
    assert_equal "Core Rules 2.0.1, p. 9", dying.fetch("effects_source_ref")

    zephyr = Character.create!(
      name: "Windborne Zephyr",
      character_class: CharacterClass.find_by!(name: "Zephyr"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced",
      level: 20
    )
    zephyr.trait_set.update!(current_hp: 0)
    dying = zephyr.derived_condition_entries.find { |entry| entry.fetch("name") == "Dying" }
    assert_equal 2, dying.fetch("actions_limited_to")
    assert_equal "Heroes 2.0.1, p. 69", dying.fetch("effects_source_ref")
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-06:AC-3 S-09:AC-3
  test "Zephyr's permanent action maximum comes from its level-twenty feature" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Zephyr")
    ancestry = Ancestry.find_by!(name: "Human")
    background = Background.find_by!(name: "Fearless")
    character_class = CharacterClass.find_by!(name: "Zephyr")
    level_nineteen = Character.create!(
      name: "Windborne Candidate",
      level: 19,
      character_class:,
      ancestry:,
      background:,
      stat_array: "balanced"
    )
    level_twenty = Character.create!(
      name: "Windborne Zephyr",
      level: 20,
      character_class:,
      ancestry:,
      background:,
      stat_array: "balanced"
    )

    assert_equal 3, level_nineteen.trait_set.max_actions
    assert_equal 4, level_twenty.trait_set.max_actions
    assert_equal 4, level_twenty.trait_set.current_actions
    assert_equal 4, level_twenty.max_actions_for
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

  # S-02:AC-1 S-05:AC-2 S-09:AC-3
  test "editing a draft stat placement refreshes armor and persisted derived stats" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    mage = Character.create!(
      name: "Reassigned Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )

    assert_equal 0, mage.stat_set.dexterity
    assert_equal 1, mage.trait_set.armor

    mage.update!(stat_assignments: { strength: 0, dexterity: 2, intelligence: 1, will: 1 })

    assert_equal 2, mage.reload.stat_set.dexterity
    assert_equal 3, mage.trait_set.armor
    assert_equal mage.armor_for + mage.derived_modifier_for(:armor_modifier), mage.trait_set.armor
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

    zephyr = Character.create!(
      name: "Armored Zephyr",
      level: 13,
      character_class: CharacterClass.find_by!(name: "Zephyr"),
      starting_equipment_choice: "starting_gold",
      stat_array: "standard"
    )
    plate = zephyr.inventory_items.create!(name: "Rusty Plate", equipped: false)
    unarmored_armor = zephyr.armor_for

    plate.update!(equipped: true)

    assert_equal 1, plate.slots
    assert_equal 10, zephyr.armor_for
    assert_equal 2 * (zephyr.stat_value("dexterity") + zephyr.stat_value("strength")), unarmored_armor
    assert_not_equal 2 * zephyr.armor_for, zephyr.armor_for, "Iron Defense doubles unarmored Armor, not worn plate"
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-06:AC-3 S-09:AC-3
  test "Zephyr gains its level-based Speed and Initiative only while unarmored" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Zephyr")
    character_class = CharacterClass.find_by!(name: "Zephyr")
    ancestry = Ancestry.find_by!(name: "Human")
    background = Background.find_by!(name: "Raised by Goblins")
    unarmored = Character.create!(
      name: "Unarmored Swift Zephyr",
      character_class:,
      ancestry:,
      background:,
      level: 9,
      stat_array: "balanced",
      starting_equipment_choice: "starting_gold"
    )
    armored = Character.create!(
      name: "Armored Swift Zephyr",
      character_class:,
      ancestry:,
      background:,
      level: 9,
      stat_array: "balanced",
      starting_equipment_choice: "starting_gold"
    )
    shielded = Character.create!(
      name: "Shielded Swift Zephyr",
      character_class:,
      ancestry:,
      background:,
      level: 9,
      stat_array: "balanced",
      starting_equipment_choice: "starting_gold"
    )
    worn_armor = armored.inventory_items.create!(name: "Rusty Mail", equipped: true)
    shielded.inventory_items.create!(name: "Wooden Buckler", equipped: true)

    assert unarmored.unarmored?
    assert_not armored.unarmored?
    assert shielded.unarmored?, "A shield adds Armor but is not body armor (Core Rules 2.0.1, p. 33)."
    assert_equal 8, unarmored.speed_for(level: 2)
    assert_equal armored.initiative_for(level: 2) + 2, unarmored.initiative_for(level: 2)
    assert_equal 10, unarmored.trait_set.speed
    assert_equal armored.trait_set.initiative + 9, unarmored.trait_set.initiative
    assert_equal unarmored.trait_set.speed, shielded.trait_set.speed
    assert_equal unarmored.trait_set.initiative, shielded.trait_set.initiative
    assert_equal unarmored.trait_set.armor + 2, shielded.trait_set.armor
    assert_equal 6, armored.trait_set.speed
    assert_equal armored.initiative_for(level: 2), armored.trait_set.initiative

    worn_armor.destroy!
    assert armored.reload.unarmored?
    assert_equal 10, armored.trait_set.speed
    assert_equal unarmored.trait_set.initiative, armored.trait_set.initiative
  end

  # S-02:AC-1 S-02:AC-2 S-02:AC-4 S-05:AC-2 S-09:AC-3
  test "equipped armor replaces the body-armor formula, uses source slots, and recalculates the sheet" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    mage = Character.create!(
      name: "Armor Loadout Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    garb = mage.starting_gear_inventory_items.find_by!(name: "Adventurer's Garb")
    plate = mage.inventory_items.create!(name: "Rusty Mail", equipped: false)
    original_armor = mage.trait_set.armor

    assert_not plate.equipped?
    assert_equal 2, plate.slots
    assert_equal original_armor, mage.trait_set.armor

    plate.update!(equipped: true)

    assert_predicate plate, :equipped?
    assert_equal 1, plate.slots
    assert_equal 1, plate.catalog_slots
    assert_not garb.reload.equipped?
    assert_equal 5, mage.reload.trait_set.armor
    assert_not mage.armor_proficient_with?(plate.armor_profile)
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "removing an equipped shield removes only its Armor bonus and snapshots equipped state" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Oathsworn")
    oathsworn = Character.create!(
      name: "Shield Loadout Oathsworn",
      character_class: CharacterClass.find_by!(name: "Oathsworn"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    shield = oathsworn.starting_gear_inventory_items.find_by!(name: "Wooden Buckler")
    armor_with_shield = oathsworn.trait_set.armor

    assert_predicate shield, :equipped?
    assert_equal armor_with_shield, oathsworn.armor_for + oathsworn.derived_modifier_for(:armor_modifier)
    assert_equal true, oathsworn.snapshot_payload.fetch("inventory_items").find { |item| item.fetch("name") == "Wooden Buckler" }.fetch("equipped")

    shield.destroy!

    assert_equal armor_with_shield - 2, oathsworn.reload.trait_set.armor
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

  # S-02:AC-1 S-02:AC-2 S-05:AC-2
  test "Songweaver's additional school must be a different school from Wind" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Songweaver")
    songweaver = CharacterClass.find_by!(name: "Songweaver")
    character = Character.new(character_class: songweaver, spell_school_choice: "Fire")

    assert_includes character.known_spell_schools, "Wind"
    assert_includes character.known_spell_schools, "Fire"
    assert_empty character.creation_issues.select { |issue| issue.fetch(:message).include?("additional spell school") }

    character.spell_school_choice = "Wind"
    issue = character.creation_issues.find { |entry| entry.fetch(:message).include?("not a legal additional spell school") }

    assert_equal "Wind is not a legal additional spell school for Songweaver.", issue.fetch(:message)
    assert_equal "Heroes 2.0.1, p. 55", issue.fetch(:source_ref)
    assert_match(/1 other school/, issue.fetch(:quote))
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
      language_choices: [ "Draconic", "Primordial" ],
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

  # S-02:AC-1 S-02:AC-4 S-05:AC-1 S-05:AC-3 S-09:AC-3
  test "background spell-choice requirements use configured names, counts, labels, and distinctness" do
    Rails.application.load_seed
    catalog = Rules::NimbleCatalog.data
    original_choices = catalog.fetch("background_spell_choices")
    background_name = "Wayward Apprentice"
    catalog["background_spell_choices"] = original_choices.merge(
      background_name => {
        "source_ref" => "Test rules, p. 1",
        "source_quote" => "Learn 2 different Utility Spells.",
        "kind" => "utility_spell_any",
        "choice_label" => "Utility Spell",
        "count" => 2,
        "distinct" => true
      }
    )

    begin
      background = Background.create!(name: background_name)
      attributes = {
        name: "Data-driven background spell hero",
        character_class: CharacterClass.find_by!(name: "Mage"),
        ancestry: Ancestry.find_by!(name: "Human"),
        background:,
        stat_array: "standard",
        language_choices: [ "Draconic", "Primordial" ],
        skill_set_attributes: { arcana: 7 }
      }
      character = Character.create!(**attributes)
      pool = character.spell_choice_pools_for(1).find { |entry| entry.fetch("name") == background_name }
      assert_equal 2, pool.fetch("count")
      assert_equal "Utility Spell", pool.fetch("choice_label")

      missing = character.creation_issues.find { |issue| issue.fetch(:source_ref) == "Test rules, p. 1" }
      assert_equal "Wayward Apprentice requires 2 Utility Spell choices.", missing.fetch(:message)
      assert_equal "Learn 2 different Utility Spells.", missing.fetch(:quote)

      spell_names = pool.fetch("options").first(2)
      character.update!(spell_choices: { background_name => { "1" => [ spell_names.first, spell_names.first ] } })
      duplicate = character.creation_issues.find { |issue| issue.fetch(:message).include?("must be different") }
      assert_equal "Wayward Apprentice choices must be different.", duplicate.fetch(:message)
      assert_equal "Test rules, p. 1", duplicate.fetch(:source_ref)

      character.update!(spell_choices: { background_name => { "1" => spell_names } })
      assert_empty character.creation_issues, character.creation_issues.map { |issue| issue.fetch(:message) }.join(" | ")
      character.finalize_creation!
      assert_equal spell_names.sort, character.reload.spells.where(tier: -1).pluck(:name).sort

      unselected_background = Character.create!(
        **attributes.merge(
          name: "Unselected background spell hero",
          background: Background.find_by!(name: "Fearless"),
          spell_choices: { background_name => { "1" => spell_names } }
        )
      )
      wrong_background = unselected_background.creation_issues.find { |issue| issue.fetch(:source_ref) == "Test rules, p. 1" }
      assert_equal "Wayward Apprentice's Utility Spell choice is not available unless that background is selected.", wrong_background.fetch(:message)
    ensure
      catalog["background_spell_choices"] = original_choices
    end
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

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "catalog resource formulas derive every class and story-subclass pool at every level" do
    Rails.application.load_seed
    stat_values = { strength: 2, dexterity: 1, intelligence: 3, will: 4 }
    stat_abbreviations = { "STR" => "strength", "DEX" => "dexterity", "INT" => "intelligence", "WIL" => "will" }
    formula_max = lambda do |formula, character_class, level|
      case formula.to_s
      when /\A\d+\z/
        formula.to_i
      when /\AMIN\(\s*(STR|DEX|INT|WIL)\s*,\s*LVL\s*\)\z/i
        [ stat_values.fetch(stat_abbreviations.fetch(Regexp.last_match(1).upcase).to_sym), level ].min
      when /\A\s*(\d+)\s*\*\s*LVL\b/i
        Regexp.last_match(1).to_i * level
      when /\bKEY\b/i
        character_class.key_stats.map { |stat| stat_values.fetch(stat.to_sym) }.max
      when /\b(STR|DEX|INT|WIL)\b/i
        stat_token = Regexp.last_match(1).upcase
        stat_value = stat_values.fetch(stat_abbreviations.fetch(stat_token).to_sym)
        multiplier = formula.match(/\b#{stat_token}\s*\*\s*(\d+)/i)&.[](1)&.to_i ||
          formula.match(/(\d+)\s*\*\s*#{stat_token}\b/i)&.[](1)&.to_i || 1
        stat_value * multiplier + (formula.match?(/\+\s*LVL/i) ? level : 0)
      else
        flunk "Unsupported catalog resource formula: #{formula.inspect}"
      end
    end

    Rules::NimbleCatalog.classes.each do |class_name, class_rules|
      character_class = CharacterClass.find_by!(name: class_name)
      subclass_names = [
        nil,
        *Array(class_rules["subclasses"]),
        *Array(class_rules["story_based_subclasses"]).map { |subclass| subclass.fetch("name") }
      ].uniq

      subclass_names.each do |subclass_name|
        class_pools = Array(class_rules.dig("resource", "pools")).reject do |pool|
          pool["subclass_name"].present? && pool["subclass_name"] != subclass_name
        end
        replaced_pool_keys = Rules::NimbleCatalog.story_subclass_resource_pool_replacements_for(class_name, subclass_name)
        class_pools.reject! { |pool| replaced_pool_keys.include?(pool.fetch("key")) }
        story_pools = Rules::NimbleCatalog.story_subclass_resource_pools_for(class_name, subclass_name)
        pools_by_key = (class_pools + story_pools).index_by { |pool| pool.fetch("key") }
        character = Character.new(character_class:, subclass_name:)

        (1..Character::MAX_LEVEL).each do |level|
          effects = character.derived_feature_effects(level:, subclass_name:).fetch("resource_max_modifiers", {})
          tracks = character.derived_resource_tracks_for(stat_values:, level:, subclass_name:)
          mana_track = tracks.find { |track| track.fetch("key") == "mana" }
          expected_mana_max = mana_track&.fetch("max")
          actual_mana_max = character.mana_max_for(stat_values:, level:)
          mana_message = "#{class_name} #{subclass_name.inspect} L#{level} Mana projection must match its canonical pool"
          expected_mana_max.nil? ? assert_nil(actual_mana_max, mana_message) : assert_equal(expected_mana_max, actual_mana_max, mana_message)

          tracks.each do |track|
            pool = pools_by_key[track.fetch("key")]
            assert pool, "#{class_name} #{subclass_name.inspect} L#{level} #{track.fetch('key')} must have a catalog definition"
            max_by_level = pool.fetch("max_by_level", {}).select { |unlock_level, _maximum| level >= unlock_level.to_i }
            expected_max = if max_by_level.any?
              max_by_level.max_by { |unlock_level, _maximum| unlock_level.to_i }.last.to_i
            elsif pool["max_formula"].present?
              formula_max.call(pool.fetch("max_formula"), character_class, level)
            end
            if expected_max.present?
              expected_max += effects.fetch(track.fetch("key"), 0).to_i
              expected_max = [ expected_max, pool.fetch("minimum_max").to_i ].max if pool.key?("minimum_max")
            end

            reference = pool["source_ref"].presence || class_rules.fetch("source_ref")
            message = "#{class_name} #{subclass_name.inspect} L#{level} #{track.fetch('key')} should follow #{pool['max_formula'].inspect} (#{reference})"
            expected_max.nil? ? assert_nil(track["max"], message) : assert_equal(expected_max, track["max"], message)
          end
        end
      end
    end
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Spellblade gains INT temporary mana once at initiative and loses it when the encounter ends" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Arcane Initiative",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Commander"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced",
      stat_assignments: { strength: 2, dexterity: 1, intelligence: 1, will: 0 }
    )
    spellblade_tracks = character.derived_resource_tracks_for(
      stat_values: { strength: 2, dexterity: 1, intelligence: 1, will: 0 },
      level: 3,
      subclass_name: "Spellblade"
    )
    mana = spellblade_tracks.find { |track| track.fetch("key") == "spellblade_initiative_mana" }
    assert_equal 1, mana.fetch("max")
    assert_equal 0, mana.fetch("current")
    assert_equal [ "encounter_end" ], mana.fetch("reset_events")

    character.update_columns(subclass_name: "Spellblade", status: "playable")
    character.trait_set.update!(resource_tracks: spellblade_tracks)
    assert_raises(ArgumentError) do
      character.begin_encounter!(feature_actions: { "unsupported_action" => { "used" => "1" } })
    end
    assert_raises(ArgumentError) do
      character.begin_encounter!(feature_actions: { "firebrand_enchant_weapon" => { "used" => "1" } })
    end
    assert_nil character.reload.encounter_started_at
    assert_equal 0, character.character_revisions.where(event_type: "initiative_roll").count

    actions_before = character.trait_set.current_actions
    revision = character.begin_encounter!(
      feature_actions: { "firebrand_enchant_weapon" => { "used" => "1", "target" => "Silver longsword" } }
    )

    assert_includes revision.summary, "Firebrand cast Enchant Weapon at Tier 2 for free on Silver longsword"
    assert_includes revision.summary, "Heroes 2.0.1, p. 77"
    assert_includes revision.summary, "resolve spell effects and any upcast at the table"
    assert_equal actions_before, character.reload.trait_set.current_actions, "Firebrand's Initiative cast is free"
    assert_equal 1, character.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "spellblade_initiative_mana" }.fetch("current")
    assert character.encounter_started_at.present?
    assert character.character_revisions.exists?(event_type: "initiative_roll")
    assert_raises(ArgumentError) { character.begin_encounter! }

    spent_tracks = character.trait_set.resource_tracks.map do |track|
      track.fetch("key") == "spellblade_initiative_mana" ? track.merge("current" => 0) : track
    end
    character.trait_set.update!(resource_tracks: spent_tracks)
    character.end_encounter!

    refreshed_mana = character.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "spellblade_initiative_mana" }
    assert_equal 0, refreshed_mana.fetch("current")
    assert_nil character.encounter_started_at
    assert character.character_revisions.exists?(event_type: "encounter_end")

    character.begin_encounter!
    character.take_safe_rest!
    assert_nil character.reload.encounter_started_at
    assert_equal 0, character.trait_set.resource_tracks.find { |track| track.fetch("key") == "spellblade_initiative_mana" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-08:AC-4 S-09:AC-3
  test "Shadowmancer minions respect min(INT, level), and Reaver replaces Pilfered Power" do
    Rails.application.load_seed
    shadowmancer = Character.create!(
      name: "Shadow Pool Hero",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Shadowmancer"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    stats = { strength: 1, dexterity: 2, intelligence: 2, will: 0 }
    ordinary_tracks = shadowmancer.derived_resource_tracks_for(stat_values: stats, level: 3, subclass_name: "Pact of the Red Dragon").index_by { |track| track.fetch("key") }
    assert_equal 2, ordinary_tracks.fetch("shadow_minions").fetch("max")
    assert_equal 2, ordinary_tracks.fetch("pilfered_power").fetch("max")

    reaver_tracks = shadowmancer.derived_resource_tracks_for(stat_values: stats, level: 3, subclass_name: "Reaver").index_by { |track| track.fetch("key") }
    assert_not reaver_tracks.key?("pilfered_power")
    assert_equal 2, reaver_tracks.fetch("shadow_minions").fetch("max")
    assert_equal 1, reaver_tracks.fetch("reaver_shadow_exploit_next_cost").fetch("current")
    assert_equal "Shadow Minions", shadowmancer.derived_resource_values_for(stat_values: stats, level: 3, subclass_name: "Reaver").fetch(:name)

    nonpositive_int_tracks = shadowmancer.derived_resource_tracks_for(
      stat_values: stats.merge(intelligence: -1),
      level: 3,
      subclass_name: "Reaver"
    ).index_by { |track| track.fetch("key") }
    assert_equal 0, nonpositive_int_tracks.fetch("shadow_minions").fetch("max")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Zephyr Initiative grants uncapped DEX Bursts plus the level-twenty bonus" do
    Rails.application.load_seed
    zephyr_class = CharacterClass.find_by!(name: "Zephyr")
    ancestry = Ancestry.find_by!(name: "Human")
    background = Background.find_by!(name: "Fearless")
    level_one = Character.create!(name: "Zephyr Before Burst", character_class: zephyr_class, ancestry:, background:, stat_array: "balanced")
    level_two = Character.create!(name: "Zephyr Initiator", level: 2, character_class: zephyr_class, ancestry:, background:, stat_array: "balanced")
    level_twenty = Character.create!(name: "Windborne Initiator", level: 20, character_class: zephyr_class, ancestry:, background:, stat_array: "balanced")

    assert_nil level_one.initiative_resource_grant
    assert_empty level_one.trait_set.resource_tracks
    assert_nil level_two.initiative_resource_grant["amount"]
    assert_equal level_two.stat_value(:dexterity), level_two.initiative_resource_amount
    bursts = level_two.trait_set.resource_tracks.sole
    assert_equal "bursts_of_speed", bursts.fetch("key")
    assert_nil bursts["max"]
    assert_equal 0, bursts.fetch("current")

    previously_capped_bursts = bursts.merge("max" => level_two.stat_value(:dexterity), "current" => level_two.stat_value(:dexterity))
    previous_tracker_state = {
      resource_tracks: [ previously_capped_bursts ],
      current_mana: nil,
      previous_max_mana: nil,
      current_resource: nil,
      previous_max_resource: nil
    }
    preserved_bursts = level_two.preserved_resource_tracks([ bursts ], previous_tracker_state)
    assert_equal previously_capped_bursts.fetch("current"), preserved_bursts.sole.fetch("current"), "changing the rule to an uncapped pool must not discard saved charges"

    level_two.begin_encounter!
    assert_equal level_two.stat_value(:dexterity), level_two.reload.trait_set.resource_tracks.sole.fetch("current")
    level_two.end_encounter!
    assert_equal 0, level_two.reload.trait_set.resource_tracks.sole.fetch("current")

    assert_equal level_twenty.stat_value(:dexterity) + 1, level_twenty.initiative_resource_amount
    level_twenty.begin_encounter!
    assert_equal level_twenty.stat_value(:dexterity) + 1, level_twenty.reload.trait_set.resource_tracks.sole.fetch("current")
    assert_includes level_twenty.character_revisions.where(event_type: "initiative_roll").sole.summary, "#{level_twenty.stat_value(:dexterity) + 1} Bursts of Speed"
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "one Initiative event applies every eligible class and subclass resource grant" do
    Rails.application.load_seed
    commander = Character.create!(
      name: "Spellblade Commander",
      level: 4,
      character_class: CharacterClass.find_by!(name: "Commander"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    commander.update_column(:subclass_name, "Spellblade")
    stat_values = Character::STAT_NAMES.index_with { |stat| commander.stat_value(stat) }
    tracks = commander.derived_resource_tracks_for(stat_values:, level: 4, subclass_name: "Spellblade")
    commander.trait_set.update!(resource_tracks: tracks)

    assert_equal [ "Fit for Any Battlefield", "Arcane Command" ], commander.initiative_resource_grants.map { |grant| grant.fetch("feature_name") }
    revision = commander.begin_encounter!
    refreshed_tracks = commander.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }

    assert_equal commander.stat_value(:strength), refreshed_tracks.fetch("combat_dice").fetch("current")
    assert_equal commander.stat_value(:intelligence), refreshed_tracks.fetch("spellblade_initiative_mana").fetch("current")
    assert_includes revision.summary, "gained #{commander.stat_value(:strength)} Combat Dice"
    assert_includes revision.summary, "gained #{commander.stat_value(:intelligence)} Arcane Command mana"

    commander.end_encounter!
    ended_tracks = commander.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal 0, ended_tracks.fetch("combat_dice").fetch("current")
    assert_equal 0, ended_tracks.fetch("spellblade_initiative_mana").fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Commander tracks Coordinated Strike uses and does not refund one spent use twice" do
    Rails.application.load_seed
    commander = Character.create!(
      name: "Vanguard Commander",
      level: 11,
      character_class: CharacterClass.find_by!(name: "Commander"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced",
      stat_assignments: { strength: 2, dexterity: 1, intelligence: 1, will: 0 }
    )
    commander.update_columns(status: "playable", subclass_name: "Champion of the Vanguard")
    stat_values = Character::STAT_NAMES.index_with { |stat| commander.stat_value(stat) }
    tracks = commander.derived_resource_tracks_for(stat_values:, level: 11, subclass_name: "Champion of the Vanguard")
    strike_uses = tracks.find { |track| track.fetch("key") == "coordinated_strike_uses" }
    initiative_refunds = tracks.find { |track| track.fetch("key") == "coordinated_strike_initiative_uses" }

    assert_equal commander.stat_value(:intelligence) + 2, strike_uses.fetch("max"), "level 9 and Vanguard level 7 each add a Safe Rest use"
    assert_equal 2, initiative_refunds.fetch("max"), "Master Commander and Survey each grant one Initiative refund"
    assert_equal [ "Fit for Any Battlefield", "Master Commander", "Survey the Battlefield" ], commander.initiative_resource_grants.map { |grant| grant.fetch("feature_name") }

    tracks = tracks.map do |track|
      track.fetch("key") == "coordinated_strike_uses" ? track.merge("current" => strike_uses.fetch("max") - 1) : track
    end
    commander.trait_set.update!(resource_tracks: tracks)
    revision = commander.begin_encounter!
    refreshed_tracks = commander.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal 1, refreshed_tracks.fetch("coordinated_strike_initiative_uses").fetch("current"), "both features cannot refund the same spent use"
    assert_equal strike_uses.fetch("max") - 1, refreshed_tracks.fetch("coordinated_strike_uses").fetch("current"), "a temporary refund does not restore the Safe Rest pool"
    assert_includes revision.summary, "regained 1 temporary Coordinated Strike use"
    assert_includes revision.summary, "regained 0 temporary Coordinated Strike use from Survey"

    commander.end_encounter!
    tracks = commander.reload.trait_set.resource_tracks.map do |track|
      track.fetch("key") == "coordinated_strike_uses" ? track.merge("current" => strike_uses.fetch("max") - 2) : track
    end
    commander.trait_set.update!(resource_tracks: tracks)
    revision = commander.begin_encounter!
    assert_equal 2, commander.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "coordinated_strike_initiative_uses" }.fetch("current")
    assert_equal 2, revision.summary.scan("regained 1 temporary Coordinated Strike use").length

    commander.end_encounter!
    commander.take_safe_rest!
    refreshed_tracks = commander.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal strike_uses.fetch("max"), refreshed_tracks.fetch("coordinated_strike_uses").fetch("current")
    assert_equal 0, refreshed_tracks.fetch("coordinated_strike_initiative_uses").fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Shepherd Initiative recharges only selected Sacred Grace and subclass uses" do
    Rails.application.load_seed
    shepherd = Character.create!(
      name: "Light Bearer Shepherd",
      level: 5,
      character_class: CharacterClass.find_by!(name: "Shepherd"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced",
      feature_choices: { "Sacred Grace" => { "5" => [ "Light Bearer", "Assist Me, My Friend!" ] } }
    )
    searing_pool = shepherd.trait_set.resource_tracks.find { |track| track.fetch("key") == "searing_light" }
    refund_pool = shepherd.trait_set.resource_tracks.find { |track| track.fetch("key") == "searing_light_initiative_uses" }
    assert_equal shepherd.stat_value(:will), searing_pool.fetch("max")
    assert_equal 1, refund_pool.fetch("max")
    assert_equal [ "Light Bearer" ], shepherd.initiative_resource_grants.map { |grant| grant.fetch("feature_name") }

    unchosen_grace = Character.create!(
      name: "Unchosen Grace Shepherd",
      level: 5,
      character_class: CharacterClass.find_by!(name: "Shepherd"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    assert_empty unchosen_grace.initiative_resource_grants
    assert_not unchosen_grace.trait_set.resource_tracks.any? { |track| track.fetch("key") == "searing_light_initiative_uses" }

    tracks = shepherd.trait_set.resource_tracks.map do |track|
      track.fetch("key") == "searing_light" ? track.merge("current" => searing_pool.fetch("max") - 1) : track
    end
    shepherd.trait_set.update!(resource_tracks: tracks)
    revision = shepherd.begin_encounter!
    assert_equal 1, shepherd.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "searing_light_initiative_uses" }.fetch("current")
    assert_includes revision.summary, "regained 1 temporary Searing Light use from Light Bearer"
    shepherd.end_encounter!
    shepherd.take_safe_rest!
    assert_equal searing_pool.fetch("max"), shepherd.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "searing_light" }.fetch("current")

    mercy = Character.create!(
      name: "Empowered Mercy Shepherd",
      level: 15,
      character_class: CharacterClass.find_by!(name: "Shepherd"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced",
      feature_choices: { "Sacred Grace" => { "5" => [ "Light Bearer", "Assist Me, My Friend!" ] } }
    )
    mercy.update_column(:subclass_name, "Luminary of Mercy")
    mercy_stats = Character::STAT_NAMES.index_with { |stat| mercy.stat_value(stat) }
    mercy_tracks = mercy.derived_resource_tracks_for(stat_values: mercy_stats, level: 15, subclass_name: "Luminary of Mercy")
    mercy_refunds = mercy_tracks.find { |track| track.fetch("key") == "searing_light_initiative_uses" }
    assert_equal 2, mercy_refunds.fetch("max"), "Light Bearer and Empowered Conduit each add one possible refund"
    assert_equal [ "Light Bearer", "Empowered Conduit" ], mercy.initiative_resource_grants.map { |grant| grant.fetch("feature_name") }
    mercy_tracks = mercy_tracks.map do |track|
      track.fetch("key") == "searing_light" ? track.merge("current" => track.fetch("max").to_i - 2) : track
    end
    mercy.trait_set.update!(resource_tracks: mercy_tracks)
    mercy.begin_encounter!
    assert_equal 2, mercy.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "searing_light_initiative_uses" }.fetch("current")
    mercy.end_encounter!

    malice = Character.create!(
      name: "Conduit of Death Shepherd",
      level: 15,
      character_class: CharacterClass.find_by!(name: "Shepherd"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    malice.update_column(:subclass_name, "Luminary of Malice")
    malice_stats = Character::STAT_NAMES.index_with { |stat| malice.stat_value(stat) }
    malice_tracks = malice.derived_resource_tracks_for(stat_values: malice_stats, level: 15, subclass_name: "Luminary of Malice")
    assert_equal [ "Conduit of Death" ], malice.initiative_resource_grants.map { |grant| grant.fetch("feature_name") }
    malice_tracks = malice_tracks.map do |track|
      track.fetch("key") == "veilwalkers_blessing_uses" ? track.merge("current" => 0) : track
    end
    malice.trait_set.update!(resource_tracks: malice_tracks)
    malice.begin_encounter!
    assert_equal 1, malice.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "veilwalkers_blessing_initiative_uses" }.fetch("current")
    malice.end_encounter!
    malice_tracks = malice.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal 0, malice_tracks.fetch("veilwalkers_blessing_initiative_uses").fetch("current")
    assert_equal 0, malice_tracks.fetch("veilwalkers_blessing_uses").fetch("current"), "encounter-end refund remains separate from the Safe Rest charge"
    malice.take_safe_rest!
    assert_equal 1, malice.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "veilwalkers_blessing_uses" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Mage Elemental Surge uses entered dice and permits only Steel Will rerolls of ones" do
    Rails.application.load_seed
    mage = Character.create!(
      name: "Controlled Surge",
      level: 17,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    mage.update_columns(status: "playable", subclass_name: "Control")
    stat_values = Character::STAT_NAMES.index_with { |stat| mage.stat_value(stat) }
    tracks = mage.derived_resource_tracks_for(stat_values:, level: 17, subclass_name: "Control")
    mage.trait_set.update!(resource_tracks: tracks)
    grant = mage.initiative_resource_grants.sole
    surge_track = tracks.find { |track| track.fetch("key") == "elemental_surge_mana" }

    assert_equal 2, mage.initiative_resource_dice_count(grant)
    assert_equal 4, mage.initiative_resource_die_sides(grant)
    assert_equal mage.stat_value(:will) + 7, mage.initiative_resource_amount(grant, dice_rolls: [ 3, 4 ])
    assert_equal "Steel Will", mage.initiative_resource_reroll_rule(grant).fetch("feature_name")
    assert_equal 0, surge_track.fetch("current")

    mage.update_column(:level, 10)
    assert_equal 1, mage.initiative_resource_dice_count(grant)
    assert_nil mage.initiative_resource_reroll_rule(grant), "Steel Will does not unlock until level 11"
    level_ten_revision = mage.begin_encounter!(dice_rolls: [ 4 ])
    assert_equal mage.stat_value(:will) + 4, mage.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "elemental_surge_mana" }.fetch("current")
    assert_includes level_ten_revision.summary, "d4 results: 4"
    mage.end_encounter!

    mage.update_column(:level, 11)
    assert_equal "Steel Will", mage.initiative_resource_reroll_rule(grant).fetch("feature_name")
    mage.update_column(:level, 17)

    initiative_revisions_before_invalid_rolls = mage.character_revisions.where(event_type: "initiative_roll").count
    assert_raises(ArgumentError) { mage.begin_encounter!(dice_rolls: [ 3 ]) }
    assert_raises(ArgumentError) { mage.begin_encounter!(dice_rolls: [ 3, 5 ]) }
    assert_raises(ArgumentError) { mage.begin_encounter!(dice_rolls: [ 3, 1.5 ]) }
    assert_raises(ArgumentError) { mage.begin_encounter!(dice_rolls: [ 3, 2 ], rerolls: [ 4, "" ]) }
    assert_nil mage.encounter_started_at
    assert_equal 0, mage.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "elemental_surge_mana" }.fetch("current")
    assert_equal initiative_revisions_before_invalid_rolls, mage.character_revisions.where(event_type: "initiative_roll").count

    mage.update_column(:subclass_name, "Chaos")
    assert_nil mage.initiative_resource_reroll_rule(grant)
    assert_raises(ArgumentError) { mage.begin_encounter!(dice_rolls: [ 1, 3 ], rerolls: [ 4, "" ]) }
    mage.update_column(:subclass_name, "Control")

    revision = mage.begin_encounter!(dice_rolls: [ 1, 3 ], rerolls: [ 4, "" ])
    assert_equal mage.stat_value(:will) + 7, mage.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "elemental_surge_mana" }.fetch("current")
    assert_includes revision.summary, "d4 results: 1 → 4, 3 (Steel Will)"

    mage.end_encounter!
    assert_equal 0, mage.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "elemental_surge_mana" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "subclass Initiative charges respect spent-use limits and expire at encounter end" do
    Rails.application.load_seed
    ancestry = Ancestry.find_by!(name: "Human")
    background = Background.find_by!(name: "Fearless")

    hunter = Character.create!(name: "Apex Tracker", level: 15, character_class: CharacterClass.find_by!(name: "Hunter"), ancestry:, background:, stat_array: "balanced")
    hunter.update_column(:subclass_name, "Shadowpath")
    hunter_stats = Character::STAT_NAMES.index_with { |stat| hunter.stat_value(stat) }
    hunter.trait_set.update!(resource_tracks: hunter.derived_resource_tracks_for(stat_values: hunter_stats, level: 15, subclass_name: "Shadowpath"))
    assert_raises(ArgumentError) { hunter.use_shadowpath_first_attack_advantage! }
    revision = hunter.begin_encounter!(
      feature_actions: { "shadowpath_hunters_mark" => { "used" => "1", "target" => "Ashen Stag" } }
    )
    assert_includes revision.summary, "Ambusher used Hunter's Mark for free on Ashen Stag"
    assert_includes revision.summary, "Heroes 2.0.1, p. 28"
    assert_equal 1, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadowpath_first_attack_advantage" }.fetch("current")
    assert_equal 1, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "thrill_of_the_hunt" }.fetch("current")
    actions_before = hunter.trait_set.current_actions
    first_attack = hunter.use_shadowpath_first_attack_advantage!
    assert_includes first_attack.summary, "Applied Ambusher's advantage to the first attack this encounter"
    assert_equal 0, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadowpath_first_attack_advantage" }.fetch("current")
    assert_equal actions_before, hunter.trait_set.current_actions
    assert_raises(ArgumentError) { hunter.use_shadowpath_first_attack_advantage! }
    hunter.end_encounter!
    assert_equal 0, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "thrill_of_the_hunt" }.fetch("current")
    assert_equal 0, hunter.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadowpath_first_attack_advantage" }.fetch("current")
    hunter.begin_encounter!
    assert_equal 1, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadowpath_first_attack_advantage" }.fetch("current")

    assignments = { strength: 0, dexterity: 2, intelligence: 1, will: 1 }
    red_dragon = Character.create!(name: "Red Dragon Pact", level: 11, character_class: CharacterClass.find_by!(name: "Shadowmancer"), ancestry:, background:, stat_array: "balanced", stat_assignments: assignments)
    red_dragon.update_column(:subclass_name, "Pact of the Red Dragon")
    red_dragon_stats = Character::STAT_NAMES.index_with { |stat| red_dragon.stat_value(stat) }
    red_dragon_tracks = red_dragon.derived_resource_tracks_for(stat_values: red_dragon_stats, level: 11, subclass_name: "Pact of the Red Dragon")
    red_dragon_tracks.map! do |track|
      track.fetch("key") == "pilfered_power" ? track.merge("current" => track.fetch("max").to_i - 1) : track
    end
    red_dragon.trait_set.update!(resource_tracks: red_dragon_tracks)
    red_dragon.begin_encounter!
    red_tracks = red_dragon.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal 1, red_tracks.fetch("red_dragon_temporary_pilfered_power").fetch("current")
    assert_equal red_tracks.fetch("pilfered_power").fetch("max").to_i - 1, red_tracks.fetch("pilfered_power").fetch("current"), "the temporary refund does not rewrite the Safe Rest pool"
    red_dragon.end_encounter!
    assert_equal 0, red_dragon.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "red_dragon_temporary_pilfered_power" }.fetch("current")

    songweaver = Character.create!(name: "Quick Wit Songweaver", level: 3, character_class: CharacterClass.find_by!(name: "Songweaver"), ancestry:, background:, stat_array: "balanced", stat_assignments: assignments)
    songweaver.update_column(:subclass_name, "Herald of Snark")
    songweaver_stats = Character::STAT_NAMES.index_with { |stat| songweaver.stat_value(stat) }
    songweaver_tracks = songweaver.derived_resource_tracks_for(stat_values: songweaver_stats, level: 3, subclass_name: "Herald of Snark")
    songweaver.trait_set.update!(resource_tracks: songweaver_tracks)
    assert_equal 0, songweaver.initiative_resource_amount, "Quick Wit cannot regain Inspiration that has not been spent"

    songweaver_tracks.map! do |track|
      track.fetch("key") == "inspiration" ? track.merge("current" => track.fetch("max").to_i - 1) : track
    end
    songweaver.trait_set.update!(resource_tracks: songweaver_tracks)
    assert_equal 1, songweaver.initiative_resource_amount, "Quick Wit regains only a previously spent use"
    songweaver.begin_encounter!
    song_tracks = songweaver.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal 1, song_tracks.fetch("quick_wit_inspiration").fetch("current")
    assert_equal song_tracks.fetch("inspiration").fetch("max").to_i - 1, song_tracks.fetch("inspiration").fetch("current")
    songweaver.end_encounter!
    assert_equal 0, songweaver.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "quick_wit_inspiration" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Swiftshift records either free Initiative option without spending a Beastshift or granting temp HP" do
    Rails.application.load_seed
    stormshifter = Character.create!(
      name: "Swiftshift Tracker",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Stormshifter"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    stormshifter.update_columns(subclass_name: "Circle of Fang & Claw", status: "playable")
    stat_values = Character::STAT_NAMES.index_with { |stat| stormshifter.stat_value(stat) }
    tracks = stormshifter.derived_resource_tracks_for(stat_values:, level: 3, subclass_name: "Circle of Fang & Claw")
    stormshifter.trait_set.update!(resource_tracks: tracks)
    beastshift_before = tracks.find { |track| track.fetch("key") == "beastshift" }.fetch("current")
    actions_before = stormshifter.trait_set.current_actions
    temp_hp_before = stormshifter.trait_set.temp_hp

    assert_raises(ArgumentError) do
      stormshifter.begin_encounter!(feature_actions: { "swiftshift_initiative" => { "used" => "1", "choice" => "Attack" } })
    end
    assert_nil stormshifter.reload.encounter_started_at
    assert_equal 0, stormshifter.character_revisions.where(event_type: "initiative_roll").count

    beastshift = stormshifter.begin_encounter!(
      feature_actions: { "swiftshift_initiative" => { "used" => "1", "choice" => "Beastshift" } }
    )
    assert_includes beastshift.summary, "Swiftshift chose Beastshift for free on Initiative"
    assert_includes beastshift.summary, "free Beastshifting grants no temporary HP"
    assert_equal beastshift_before, stormshifter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "beastshift" }.fetch("current")
    assert_equal actions_before, stormshifter.trait_set.current_actions
    assert_equal temp_hp_before, stormshifter.trait_set.temp_hp

    stormshifter.end_encounter!
    move = stormshifter.begin_encounter!(
      feature_actions: { "swiftshift_initiative" => { "used" => "1", "choice" => "Move" } }
    )
    assert_includes move.summary, "Swiftshift chose Move for free on Initiative"
    assert_not_includes move.summary, "temporary HP"

    stormshifter.end_encounter!
    unused = stormshifter.begin_encounter!
    assert_equal "Initiative recorded; no optional feature action taken", unused.summary
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Reaver's level-15 initiative feature is once per encounter and respects its minion limit" do
    Rails.application.load_seed
    shadowmancer = Character.create!(
      name: "Reaver Initiative",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Shadowmancer"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced",
      stat_assignments: { strength: 1, dexterity: 2, intelligence: 1, will: 0 },
      language_choices: [ "Elvish" ]
    )
    shadowmancer.update_columns(level: 15, status: "playable", subclass_name: "Reaver")
    stat_values = Character::STAT_NAMES.index_with { |stat| shadowmancer.stat_value(stat) }
    tracks = shadowmancer.derived_resource_tracks_for(stat_values:, level: 15, subclass_name: "Reaver")
    assert_equal 1, tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("max")
    shadowmancer.trait_set.update!(resource_tracks: tracks)

    revision = shadowmancer.begin_encounter!

    assert_includes revision.summary, "summoned 1 free Shadow Minions"
    assert_equal 1, shadowmancer.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
    assert shadowmancer.encounter_started_at.present?
    assert_raises(ArgumentError) { shadowmancer.begin_encounter! }

    shadowmancer.end_encounter!
    assert_equal 0, shadowmancer.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
    assert_nil shadowmancer.encounter_started_at
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

  # S-02:AC-1 S-02:AC-2 S-07:AC-2 S-09:AC-3
  test "Safe Rest healing and temporary HP expiration follow catalog values" do
    Rails.application.load_seed
    catalog = Rules::NimbleCatalog.data
    original_resting_rules = catalog.fetch("resting")
    changed_resting_rules = original_resting_rules.deep_dup
    changed_resting_rules.fetch("safe_rest").merge!("wounds_healed" => 2, "temporary_hit_points_expire" => false)
    catalog["resting"] = changed_resting_rules

    begin
      character = Character.create!(
        name: "Catalog Rest Hero",
        character_class: CharacterClass.find_by!(name: "Oathsworn"),
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        stat_array: "balanced"
      )
      character.trait_set.update!(current_hp: 2, current_hit_dice: 0, current_wounds: 3, temp_hp: 5)

      character.take_safe_rest!

      assert_equal character.trait_set.max_hp, character.reload.trait_set.current_hp
      assert_equal character.trait_set.max_hit_dice, character.trait_set.current_hit_dice
      assert_equal 1, character.trait_set.current_wounds
      assert_equal 5, character.trait_set.temp_hp
    ensure
      catalog["resting"] = original_resting_rules
    end
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

  # S-02:AC-1 S-02:AC-2 S-07:AC-2 S-09:AC-3
  test "Field Rest die result and stat modifier follow catalog rules" do
    Rails.application.load_seed
    catalog = Rules::NimbleCatalog.data
    original_resting_rules = catalog.fetch("resting")
    changed_resting_rules = original_resting_rules.deep_dup
    changed_resting_rules.fetch("field_rests").fetch("catch_breath").merge!("hit_die_result" => "maximum", "stat_modifier" => "intelligence")
    catalog["resting"] = changed_resting_rules

    begin
      mage = Character.create!(
        name: "Catalog Field Rest Mage",
        character_class: CharacterClass.find_by!(name: "Mage"),
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        stat_array: "standard",
        stat_assignments: { strength: -1, dexterity: 0, intelligence: 2, will: 2 }
      )
      mage.trait_set.update!(current_hp: 0, current_hit_dice: 1)
      expected_healing = [ mage.trait_set.max_hp, 6 + mage.stat_value("intelligence") ].min

      result = mage.perform_field_rest!(mode: "catch_breath", hit_dice_count: 1, die_rolls: [ "1" ])

      assert_equal expected_healing, result.fetch(:hp_recovered)
      assert_equal expected_healing, mage.reload.trait_set.current_hp
    ensure
      catalog["resting"] = original_resting_rules
    end
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
