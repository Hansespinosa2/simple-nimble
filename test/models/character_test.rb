require "test_helper"

class CharacterTest < ActiveSupport::TestCase
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
    ancestry = Ancestry.create!(name: "Background Change Ancestry", size: "Medium")
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
      level: 1,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )

    assert_equal 12, character.trait_set.save_dc
    assert_equal 7, character.trait_set.max_mana
    assert_equal 7, character.trait_set.current_mana
    assert_equal "Mana", character.trait_set.resource_name
    assert_equal 2, character.trait_set.initiative
    assert_equal(-1, character.trait_set.armor)
    assert_includes character.starting_equipment, "Staff"
    assert_includes character.inventory, "Adventurer's Garb"
    assert_includes character.character_class.armor_proficiencies, "cloth"

    character.trait_set.update!(current_mana: 3)
    character.update!(stat_array: "min_max")

    assert_equal 10, character.trait_set.max_mana
    assert_equal 3, character.trait_set.current_mana
  end
end
