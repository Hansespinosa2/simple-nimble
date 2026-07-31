require "test_helper"

class CharacterTest < ActiveSupport::TestCase
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
    assert_equal 30, character.trait_set.speed
    assert_equal 1, character.trait_set.current_hit_dice
    assert_equal 1, character.trait_set.max_hit_dice
    assert_equal 0, character.trait_set.armor
    assert_equal 6, character.trait_set.current_wounds
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
    assert_equal 29, character.trait_set.speed
    assert_equal 3, character.trait_set.current_hit_dice
    assert_equal 3, character.trait_set.max_hit_dice
    assert_equal 4, character.trait_set.armor
    assert_equal 7, character.trait_set.current_wounds
    assert_equal 7, character.trait_set.max_wounds
    assert_equal "1d10", character.trait_set.hit_die
    assert_equal 9, character.trait_set.current_hp
    assert_equal 9, character.trait_set.max_hp
  end
end
