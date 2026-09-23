require "test_helper"

# S-01:AC-2 S-01:AC-3 S-04:AC-3 S-06:AC-1 S-06:AC-2 S-06:AC-3 S-06:AC-4 S-06:AC-5 S-06:AC-6 S-07:AC-1 S-07:AC-2 S-07:AC-3 S-07:AC-5
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
      ruleset_version: ruleset,
      skill_set_attributes: { arcana: 4 }
    )
    @character.finalize_creation!
    @character.update_columns(level: 3, status: "playable")
    @character.skill_set.update!(arcana: @character.skill_set.arcana + 2)
  end

  test "the planner explains required choices and previews without persisting" do
    level_up = @character.level_ups.build(from_level: 3, to_level: 4, skill_name: "might", hit_die_roll_one: 2, hit_die_roll_two: 8)
    planner = LevelUpPlanner.new(@character, level_up)
    preview = planner.preview

    assert_not planner.valid?
    assert_includes planner.explanations.map { |explanation| explanation[:message] }, "Choose a key stat to increase."
    assert_equal 4, preview.fetch("level")
    assert_equal 24, preview.fetch("traits").fetch("max_hp")
    assert_equal 8, preview.fetch("hp_gain")
    assert_equal 3, @character.level
    assert_equal 16, @character.trait_set.max_hp
  end

  test "finalizing a legal level-up applies a skill, stat, derived values, and revision" do
    level_up = @character.level_ups.create!(
      from_level: 3,
      to_level: 4,
      skill_name: "might",
      stat_name: "strength",
      hit_die_roll_one: 2,
      hit_die_roll_two: 8
    )
    original_revisions = @character.character_revisions.count

    LevelUpService.finalize!(level_up)
    @character.reload

    assert_equal 4, @character.level
    assert @character.playable?
    assert_equal 3, @character.stat_set.strength
    assert_equal 4, @character.skill_set.might
    assert_equal 24, @character.trait_set.max_hp
    assert_equal original_revisions + 1, @character.character_revisions.count
    assert level_up.reload.finalized?
    assert_equal 4, level_up.preview.fetch("level")
  end

  test "an illegal stat choice cannot be finalized" do
    level_up = @character.level_ups.create!(
      from_level: 3,
      to_level: 4,
      skill_name: "might",
      stat_name: "will",
      hit_die_roll_one: 2,
      hit_die_roll_two: 8
    )

    assert_raises(ActiveRecord::RecordInvalid) { LevelUpService.finalize!(level_up) }
    assert_equal 3, @character.reload.level
    assert level_up.reload.draft?
    assert_includes level_up.errors.full_messages, "Will is not eligible for this level's stat increase."
  end

  test "a skill at the maximum cannot be selected again" do
    @character.skill_set.update!(might: 12)
    level_up = @character.level_ups.build(from_level: 3, to_level: 4, skill_name: "might", stat_name: "strength", hit_die_roll_one: 2, hit_die_roll_two: 8)
    planner = LevelUpPlanner.new(@character, level_up)

    assert_not planner.valid?
    assert_includes planner.explanations.map { |explanation| explanation[:message] }, "Might is already at the +12 skill maximum."
  end

  test "a finalized transition cannot be applied twice" do
    level_up = LevelUp.new(from_level: 3, to_level: 4, skill_name: "might", stat_name: "strength", hit_die_roll_one: 2, hit_die_roll_two: 8, status: "finalized")
    planner = LevelUpPlanner.new(@character, level_up)

    assert_not planner.valid?
    assert_includes planner.explanations.map { |explanation| explanation[:message] }, "This level-up has already been finalized."
  end

  test "a stale or tampered starting level cannot be finalized" do
    level_up = @character.level_ups.create!(
      from_level: 2,
      to_level: 4,
      skill_name: "might",
      stat_name: "strength",
      hit_die_roll_one: 2,
      hit_die_roll_two: 8
    )

    assert_raises(ActiveRecord::RecordInvalid) { LevelUpService.finalize!(level_up) }
    assert_equal 3, @character.reload.level
    assert level_up.reload.draft?
    assert_includes level_up.errors.full_messages, "Level-up must start from the character's current level."
  end

  test "finalizing a level-up preserves unrelated game state" do
    @character.update!(description: "A scarred veteran", conditions: "Poisoned", inventory: "Torch", game_notes: "Ask about the ferryman.")
    @character.trait_set.update!(current_hp: 7, current_wounds: 2, current_actions: 1, temp_hp: 3)
    level_up = @character.level_ups.create!(from_level: 3, to_level: 4, skill_name: "might", stat_name: "strength", hit_die_roll_one: 2, hit_die_roll_two: 8)

    LevelUpService.finalize!(level_up)
    @character.reload

    assert_equal "A scarred veteran", @character.description
    assert_equal "Poisoned", @character.conditions
    assert_equal "Torch", @character.inventory
    assert_equal "Ask about the ferryman.", @character.game_notes
    assert_equal 7, @character.trait_set.current_hp
    assert_equal 2, @character.trait_set.current_wounds
    assert_equal 1, @character.trait_set.current_actions
    assert_equal 3, @character.trait_set.temp_hp
  end

  test "level twenty requires and applies two different stat increases" do
    @character.update_columns(level: 19, status: "playable")
    @character.skill_set.update!(lore: 12, examination: 4)
    level_up = @character.level_ups.create!(
      from_level: 19,
      to_level: 20,
      skill_name: "might",
      stat_name: "strength",
      second_stat_name: "dexterity",
      hit_die_roll_one: 2,
      hit_die_roll_two: 8
    )

    LevelUpService.finalize!(level_up)
    @character.reload

    assert_equal 20, @character.level
    assert_equal 3, @character.stat_set.strength
    assert_equal 3, @character.stat_set.dexterity
    assert_equal "any_two", level_up.preview.fetch("stat_increase_type")
  end

  test "a level-up can move one skill point without making the source negative" do
    level_up = @character.level_ups.build(
      from_level: 3,
      to_level: 4,
      skill_name: "arcana",
      skill_from: "might",
      stat_name: "strength",
      hit_die_roll_one: 2,
      hit_die_roll_two: 8
    )
    planner = LevelUpPlanner.new(@character, level_up)

    assert planner.valid?
    assert_equal 8, planner.preview.fetch("skills").fetch("arcana")
    assert_equal 2, planner.preview.fetch("skills").fetch("might")
  end

  test "level twenty rejects a duplicate second stat" do
    @character.update_columns(level: 19, status: "playable")
    @character.skill_set.update!(lore: 12, examination: 4)
    level_up = @character.level_ups.build(
      from_level: 19,
      to_level: 20,
      skill_name: "might",
      stat_name: "strength",
      second_stat_name: "strength",
      hit_die_roll_one: 2,
      hit_die_roll_two: 8
    )

    planner = LevelUpPlanner.new(@character, level_up)

    assert_not planner.valid?
    assert_includes planner.explanations.map { |explanation| explanation[:message] }, "Choose two different stats to increase."
  end

  test "a hit die roll outside the character die is blocked with a source explanation" do
    level_up = @character.level_ups.build(
      from_level: 3,
      to_level: 4,
      skill_name: "might",
      stat_name: "strength",
      hit_die_roll_one: 2,
      hit_die_roll_two: 11
    )

    planner = LevelUpPlanner.new(@character, level_up)

    assert_not planner.valid?
    issue = planner.issues.find { |item| item[:message].include?("Hit Die roll") }
    assert_equal "Chapter 3, Derived Values", issue.fetch(:source_ref)
  end

  test "level-up preview preserves both ancestry and background modifiers" do
    background = Background.create!(
      name: "Level-Up Structured Background",
      description: "Flat rules for preview coverage.",
      initiative_modifier: 1,
      armor_modifier: -1,
      max_hit_dice_modifier: 1,
      max_wounds_modifier: 1
    )
    @character.update!(background: background)
    level_up = @character.level_ups.build(
      from_level: 3,
      to_level: 4,
      skill_name: "might",
      stat_name: "strength",
      hit_die_roll_one: 2,
      hit_die_roll_two: 8
    )

    preview = LevelUpPlanner.new(@character, level_up).preview

    assert_equal 5, preview.fetch("traits").fetch("max_hit_dice")
    assert_equal 3, preview.fetch("traits").fetch("initiative")
    assert_equal 1, preview.fetch("traits").fetch("armor")
    assert_equal 7, preview.fetch("traits").fetch("max_wounds")
  end
end
