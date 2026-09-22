require "test_helper"

# S-04:AC-3 S-06:AC-1 S-06:AC-2 S-06:AC-3 S-06:AC-4 S-06:AC-5 S-06:AC-6 S-07:AC-1 S-07:AC-2 S-07:AC-3
class LevelUpTest < ActiveSupport::TestCase
  setup do
    ruleset = RulesetVersion.find_or_create_by!(name: "Nimble", version: "v2.0.1")
    character_class = CharacterClass.create!(
      name: "Level-Up Warrior",
      key_stat_one: "strength",
      key_stat_two: "dexterity",
      hit_die: "1d10",
      starting_hp: 16,
      save_bonus_stat: "strength",
      save_penalty_stat: "intelligence"
    )
    ancestry = Ancestry.create!(name: "Level-Up Human", size: "Medium")
    background = Background.create!(name: "Level-Up Background", description: "No prerequisite")
    @character = Character.create!(
      name: "Level-Up Hero",
      level: 1,
      character_class: character_class,
      ancestry: ancestry,
      background: background,
      stat_array: "standard",
      ruleset_version: ruleset
    )
    @character.finalize_creation!
    @character.update_columns(level: 3, status: "playable")
  end

  test "the planner explains required choices and previews without persisting" do
    level_up = @character.level_ups.build(from_level: 3, to_level: 4, skill_name: "might")
    planner = LevelUpPlanner.new(@character, level_up)

    assert_not planner.valid?
    assert_includes planner.explanations.map { |explanation| explanation[:message] }, "Choose a key stat to increase."
    assert_equal 3, @character.level
    assert_equal 16, @character.trait_set.max_hp
  end

  test "finalizing a legal level-up applies a skill, stat, derived values, and revision" do
    level_up = @character.level_ups.create!(
      from_level: 3,
      to_level: 4,
      skill_name: "might",
      stat_name: "strength"
    )
    original_revisions = @character.character_revisions.count

    LevelUpService.finalize!(level_up)
    @character.reload

    assert_equal 4, @character.level
    assert @character.playable?
    assert_equal 3, @character.stat_set.strength
    assert_equal 4, @character.skill_set.might
    assert_equal 29, @character.trait_set.max_hp
    assert_equal original_revisions + 1, @character.character_revisions.count
    assert level_up.reload.finalized?
    assert_equal 4, level_up.preview.fetch("level")
  end

  test "an illegal stat choice cannot be finalized" do
    level_up = @character.level_ups.create!(
      from_level: 3,
      to_level: 4,
      skill_name: "might",
      stat_name: "will"
    )

    assert_raises(ActiveRecord::RecordInvalid) { LevelUpService.finalize!(level_up) }
    assert_equal 3, @character.reload.level
    assert level_up.reload.draft?
    assert_includes level_up.errors.full_messages, "Will is not eligible for this level's stat increase."
  end
end
