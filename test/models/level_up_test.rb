require "test_helper"

# S-01:AC-2 S-01:AC-3 S-04:AC-3 S-06:AC-1 S-06:AC-2 S-06:AC-3 S-06:AC-4 S-06:AC-5 S-06:AC-6 S-07:AC-1 S-07:AC-2 S-07:AC-3 S-07:AC-5
class LevelUpTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Berserker")
    ruleset = RulesetVersion.find_or_create_by!(name: "Nimble", version: "v2.0.1")
    character_class = CharacterClass.find_by!(name: "Berserker")
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
    @character.update_columns(level: 3, status: "playable", subclass_name: "Path of the Red Mist")
    @character.skill_set.update!(arcana: @character.skill_set.arcana + 2)
  end

  test "the planner explains required choices and previews without persisting" do
    level_up = @character.level_ups.build(from_level: 3, to_level: 4, skill_name: "might", hit_die_roll_one: 2, hit_die_roll_two: 8)
    planner = LevelUpPlanner.new(@character, level_up)
    preview = planner.preview

    assert_not planner.valid?
    assert_includes planner.explanations.map { |explanation| explanation[:message] }, "Choose a key stat to increase."
    assert_equal 4, preview.fetch("level")
    assert_equal 28, preview.fetch("traits").fetch("max_hp")
    assert_equal 8, preview.fetch("hp_gain")
    assert_equal 3, @character.level
    assert_equal 20, @character.trait_set.max_hp
  end

  # S-06:AC-3 S-09:AC-3
  test "the planner preserves an entered Hit Die roll when generating a missing roll" do
    level_up = @character.level_ups.build(from_level: 3, to_level: 4, hit_die_roll_one: 4)
    generated_sides = []
    random_number = ->(sides) { generated_sides << sides; 6 }
    planner = LevelUpPlanner.new(@character, level_up, random_number:)

    assert_equal 4, level_up.hit_die_roll_one
    assert_equal 7, level_up.hit_die_roll_two
    assert_equal [ 12 ], generated_sides, "only the missing die should be rolled using the class Hit Die size"
    assert_equal 7, planner.preview.fetch("hp_gain"), "the higher preserved/generated roll determines max HP increase"
    assert_equal 27, planner.preview.fetch("traits").fetch("max_hp")
  end

  test "finalizing a legal level-up applies a skill, stat, derived values, and revision" do
    level_up = @character.level_ups.create!(
      from_level: 3,
      to_level: 4,
      skill_name: "might",
      stat_name: "strength",
      feature_choices: legal_feature_choices_for(4),
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
    assert_equal 28, @character.trait_set.max_hp
    assert_equal original_revisions + 1, @character.character_revisions.count
    assert level_up.reload.finalized?
    assert_equal 4, level_up.preview.fetch("level")
  end

  # S-02:AC-1 S-02:AC-2 S-06:AC-3 S-06:AC-4 S-09:AC-3
  test "level-up preview and application apply Zephyr's permanent action increase without refilling actions" do
    character = Character.create!(
      name: "Windborne Level-Up",
      level: 19,
      character_class: CharacterClass.find_by!(name: "Zephyr"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    level_up = character.level_ups.build(
      from_level: 19,
      to_level: 20,
      skill_name: "might",
      stat_name: "strength",
      second_stat_name: "dexterity",
      hit_die_roll_one: 4,
      hit_die_roll_two: 7
    )
    preview = LevelUpPlanner.new(character, level_up).preview
    action_explanation = preview.fetch("explanations").find { |explanation| explanation.fetch(:message).include?("Maximum actions") }

    assert_equal 4, preview.fetch("traits").fetch("max_actions")
    assert_equal "Heroes 2.0.1, p. 69", action_explanation.fetch(:source_ref)
    assert_includes action_explanation.fetch(:quote), "Permanently gain 1 action"

    LevelUpService.send(:apply_preview!, character, preview)
    assert_equal 4, character.reload.trait_set.max_actions
    assert_equal 3, character.trait_set.current_actions, "the permanent ceiling rises without refilling spent actions"
  end

  # S-02:AC-1 S-02:AC-2 S-06:AC-2 S-07:AC-2 S-09:AC-3
  test "Hit Dice maximum and level-up gain follow the catalog progression" do
    original_catalog = Rules::NimbleCatalog.data
    changed_catalog = original_catalog.deep_dup
    progression = changed_catalog.fetch("derived_values").fetch("hit_dice_progression")
    progression["increase_per_level"] = 2
    progression["increase_source_ref"] = "Test rules, p. 99"
    progression["increase_source_quote"] = "Test rule: max Hit Dice grow by 2."
    Rules::NimbleCatalog.instance_variable_set(:@data, changed_catalog)

    begin
      @character.trait_set.update!(max_hit_dice: 3, current_hit_dice: 1)
      level_up = @character.level_ups.create!(
        from_level: 3,
        to_level: 4,
        skill_name: "might",
        stat_name: "strength",
        feature_choices: legal_feature_choices_for(4),
        hit_die_roll_one: 2,
        hit_die_roll_two: 8
      )
      planner = LevelUpPlanner.new(@character, level_up)
      preview = planner.preview
      hit_dice_explanation = preview.fetch("explanations").find { |explanation| explanation.fetch(:message).include?("Max Hit Dice") }

      assert planner.valid?, planner.explanations.map { |explanation| explanation[:message] }.join(" | ")
      assert_equal 7, preview.fetch("traits").fetch("max_hit_dice")
      assert_equal 3, preview.fetch("traits").fetch("current_hit_dice")
      assert_equal "Test rules, p. 99", hit_dice_explanation.fetch(:source_ref)
      assert_equal "Test rule: max Hit Dice grow by 2.", hit_dice_explanation.fetch(:quote)

      LevelUpService.finalize!(level_up)
      @character.reload

      assert_equal 7, @character.trait_set.max_hit_dice
      assert_equal 3, @character.trait_set.current_hit_dice
    ensure
      Rules::NimbleCatalog.instance_variable_set(:@data, original_catalog)
    end
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

  test "skill maximum validation follows the structured rules value" do
    max_skill = Rules::NimbleCatalog.derived_values.fetch("max_skill").to_i
    @character.skill_set.update!(might: max_skill)
    level_up = @character.level_ups.build(from_level: 3, to_level: 4, skill_name: "might", stat_name: "strength", feature_choices: legal_feature_choices_for(4), hit_die_roll_one: 2, hit_die_roll_two: 8)
    planner = LevelUpPlanner.new(@character, level_up)

    assert_equal max_skill, planner.max_skill_value
    assert_not planner.skill_options.include?("might")
    assert_not planner.valid?
    assert_includes planner.explanations.map { |explanation| explanation[:message] }, "Might is already at the +#{max_skill} skill maximum."
    skill_issue = planner.issues.find { |issue| issue.fetch(:message).include?("skill maximum") }
    assert_equal "Core Rules 2.0.1, p. 8", skill_issue.fetch(:source_ref)
  end

  test "stat maximum validation follows the structured rules value" do
    max_stat = Rules::NimbleCatalog.derived_values.fetch("max_stat").to_i
    @character.stat_set.update!(strength: max_stat)
    level_up = @character.level_ups.build(from_level: 3, to_level: 4, skill_name: "might", stat_name: "strength", feature_choices: legal_feature_choices_for(4), hit_die_roll_one: 2, hit_die_roll_two: 8)
    planner = LevelUpPlanner.new(@character, level_up)

    assert_equal max_stat, planner.max_stat_value
    assert_not planner.valid?
    assert_includes planner.explanations.map { |explanation| explanation[:message] }, "Strength is already at the +#{max_stat} stat maximum."
    stat_issue = planner.issues.find { |issue| issue.fetch(:message).include?("stat maximum") }
    assert_equal "Core Rules 2.0.1, p. 6", stat_issue.fetch(:source_ref)
  end

  test "stat increase count and amount from the rules catalog drive preview and persisted values" do
    original_catalog_data = Rules::NimbleCatalog.data
    overridden_catalog_data = original_catalog_data.deep_dup
    key_mechanic = overridden_catalog_data.fetch("derived_values").fetch("stat_increase_mechanics").fetch("key")
    key_mechanic["amount"] = 2
    key_mechanic["choice_count"] = 2
    original_strength = @character.stat_value("strength")
    original_dexterity = @character.stat_value("dexterity")
    original_might = @character.skill_value("might")
    level_up = @character.level_ups.create!(
      from_level: 3,
      to_level: 4,
      skill_name: "might",
      stat_name: "strength",
      second_stat_name: "dexterity",
      feature_choices: legal_feature_choices_for(4),
      hit_die_roll_one: 2,
      hit_die_roll_two: 8
    )

    Rules::NimbleCatalog.instance_variable_set(:@data, overridden_catalog_data)
    begin
      planner = LevelUpPlanner.new(@character, level_up)
      assert planner.valid?, planner.explanations.map { |explanation| explanation[:message] }.join(" | ")
      assert_equal original_strength + 2, planner.preview.fetch("stats").fetch("strength")
      assert_equal original_dexterity + 2, planner.preview.fetch("stats").fetch("dexterity")
      assert_equal original_might + 3, planner.preview.fetch("skills").fetch("might")
      assert_includes planner.preview.fetch("explanations").map { |explanation| explanation[:quote] },
        "At levels 4, 8, 12, and 16, increase 2 different Key Stats (STR or DEX) by +2."

      LevelUpService.finalize!(level_up)
      assert_equal original_strength + 2, @character.reload.stat_value("strength")
      assert_equal original_dexterity + 2, @character.stat_value("dexterity")
      assert_equal original_might + 3, @character.skill_value("might")
    ensure
      Rules::NimbleCatalog.instance_variable_set(:@data, original_catalog_data)
    end
  end

  test "skill choices exclude a target that stat and level increases would push past the cap" do
    @character.update_columns(level: 15, status: "playable")
    @character.skill_set.update!(might: 11, arcana: 9)
    level_up = @character.level_ups.build(
      from_level: 15,
      to_level: 16,
      skill_name: "might",
      stat_name: "strength",
      hit_die_roll_one: 2,
      hit_die_roll_two: 8
    )
    planner = LevelUpPlanner.new(@character, level_up)

    assert_equal 18, @character.skill_point_budget
    assert_equal 18, @character.skill_points_spent
    assert_equal 11, @character.skill_value("might")
    assert_not_includes planner.skill_options, "might"
    assert_includes planner.issues.map { |issue| issue.fetch(:message) },
      "Might would exceed the +12 skill maximum after this level's increases."
  end

  test "the catalog maximum level is enforced by the model and level-up planner" do
    maximum = Rules::NimbleCatalog.derived_values.fetch("max_level").to_i
    assert_equal maximum, Character::MAX_LEVEL

    overleveled = Character.new(level: maximum + 1)
    assert_not overleveled.valid?
    assert_includes overleveled.errors.attribute_names, :level

    @character.update_columns(level: maximum, status: "playable")
    level_up = @character.level_ups.build(from_level: maximum, to_level: maximum + 1)
    planner = LevelUpPlanner.new(@character, level_up)
    maximum_issue = planner.issues.find { |issue| issue.fetch(:message) == "This character is already at the maximum level." }

    assert_equal maximum, planner.max_level_value
    assert_equal "Heroes 2.0.1, class progressions", maximum_issue.fetch(:source_ref)
    assert_equal "Each published class progression ends at level 20.", maximum_issue.fetch(:quote)
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
    level_up = @character.level_ups.create!(from_level: 3, to_level: 4, skill_name: "might", stat_name: "strength", feature_choices: legal_feature_choices_for(4), hit_die_roll_one: 2, hit_die_roll_two: 8)

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

  test "the catalog maximum level requires and applies two different stat increases" do
    maximum_level = Character::MAX_LEVEL
    @character.update_columns(level: maximum_level - 1, status: "playable")
    @character.skill_set.update!(lore: 12, examination: 4)
    level_up = @character.level_ups.create!(
      from_level: maximum_level - 1,
      to_level: maximum_level,
      skill_name: "might",
      stat_name: "strength",
      second_stat_name: "dexterity",
      hit_die_roll_one: 2,
      hit_die_roll_two: 8
    )

    LevelUpService.finalize!(level_up)
    @character.reload

    assert_equal maximum_level, @character.level
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
      feature_choices: legal_feature_choices_for(4),
      hit_die_roll_one: 2,
      hit_die_roll_two: 8
    )
    planner = LevelUpPlanner.new(@character, level_up)

    assert planner.valid?
    assert_equal 8, planner.preview.fetch("skills").fetch("arcana")
    assert_equal 2, planner.preview.fetch("skills").fetch("might")
  end

  test "the catalog maximum level rejects a duplicate second stat" do
    maximum_level = Character::MAX_LEVEL
    @character.update_columns(level: maximum_level - 1, status: "playable")
    @character.skill_set.update!(lore: 12, examination: 4)
    level_up = @character.level_ups.build(
      from_level: maximum_level - 1,
      to_level: maximum_level,
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

  test "level three requires and persists a legal subclass choice" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Subclass Hero",
      character_class: CharacterClass.find_by!(name: "Berserker"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      skill_set_attributes: { might: 7 }
    )
    character.finalize_creation!
    character.update_columns(level: 2, status: "playable")
    character.skill_set.update!(might: 8)
    level_up = character.level_ups.create!(
      from_level: 2,
      to_level: 3,
      skill_name: "might",
      subclass_name: "Path of the Red Mist",
      hit_die_roll_one: 4,
      hit_die_roll_two: 2
    )

    assert_empty character.creation_issues, character.creation_issues.map { |issue| issue[:message] }.join(" | ")
    planner = LevelUpPlanner.new(character, level_up)
    assert planner.valid?, planner.explanations.map { |explanation| explanation[:message] }.join(" | ")
    LevelUpService.finalize!(level_up)

    assert_equal 3, character.reload.level
    assert_equal "Path of the Red Mist", character.subclass_name
    assert_equal "Path of the Red Mist", level_up.reload.preview.fetch("subclass")
    assert_includes level_up.reload.preview.fetch("progression").fetch("features"), "Bloodlust"
    assert_includes level_up.reload.preview.fetch("progression").fetch("subclass_features"), "Blood Frenzy"
  end

  test "level three blocks a missing or unknown subclass choice" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Subclass Choice Hero",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Draconic", "Primordial" ],
      skill_set_attributes: { arcana: 7 }
    )
    character.finalize_creation!
    character.update_columns(level: 2, status: "playable")
    character.skill_set.update!(arcana: 8)

    missing = character.level_ups.build(from_level: 2, to_level: 3, skill_name: "arcana", hit_die_roll_one: 3, hit_die_roll_two: 2)
    invalid = character.level_ups.build(from_level: 2, to_level: 3, skill_name: "arcana", subclass_name: "Berserker", hit_die_roll_one: 3, hit_die_roll_two: 2)

    missing_planner = LevelUpPlanner.new(character, missing)
    assert_includes missing_planner.explanations.map { |explanation| explanation[:message] }, "Choose a subclass for Mage at level #{character.character_class.subclass_choice_level}."
    assert_includes LevelUpPlanner.new(character, invalid).explanations.map { |explanation| explanation[:message] }, "Berserker is not a legal subclass for Mage."

    choice_level = character.character_class.subclass_choice_level
    character.update_columns(level: choice_level, status: "playable")
    assert_includes character.creation_issues.map { |issue| issue[:message] }, "Choose a Mage subclass before playing at level #{choice_level}."
  end

  # S-02:AC-1 S-02:AC-4 S-06:AC-2 S-06:AC-5
  test "story-based subclasses are not offered as level-three choices" do
    Rails.application.load_seed
    story_subclasses = {
      "Commander" => "Spellblade",
      "Hunter" => "Beastmaster",
      "Oathsworn" => "Oathbreaker",
      "Shadowmancer" => "Reaver"
    }

    story_subclasses.each do |class_name, story_subclass|
      character_class = CharacterClass.find_by!(name: class_name)
      creation_skill = Character::SKILL_TO_STAT.find { |_skill, stat| character_class.key_stats.include?(stat) }.first
      character = Character.create!(
        name: "#{class_name} Story Choice Hero",
        character_class: character_class,
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        stat_array: "standard",
        language_choices: character_class.key_stats.include?("intelligence") ? [ "Draconic", "Primordial" ] : []
      )
      character.skill_set.update!(creation_skill => character.skill_initial_value(creation_skill) + 4)
      character.finalize_creation!
      character.update_columns(level: 2, status: "playable")
      character.skill_set.update!(creation_skill => character.skill_value(creation_skill) + 1)

      level_up = character.level_ups.build(
        from_level: 2,
        to_level: 3,
        skill_name: "might",
        subclass_name: story_subclass,
        hit_die_roll_one: 1,
        hit_die_roll_two: 1
      )
      planner = LevelUpPlanner.new(character, level_up)

      assert_includes character_class.known_subclass_options, story_subclass
      assert_not_includes planner.subclass_options, story_subclass
      story_issue = planner.issues.find { |issue| issue.fetch(:message).include?(story_subclass) }
      assert_equal "#{story_subclass} is story-based and requires a GM-approved story change, not an ordinary level-up choice.", story_issue.fetch(:message)
      assert_equal "Heroes 2.0.1, p. 73", story_issue.fetch(:source_ref)
      assert_match(/GM's discretion/, story_issue.fetch(:quote))

      character.update_columns(level: 3, status: "playable", subclass_name: character_class.subclass_options.first)
      character.skill_set.update!(creation_skill => character.skill_value(creation_skill) + 1)
      replacement = character.level_ups.build(
        from_level: 3,
        to_level: 4,
        skill_name: creation_skill,
        subclass_name: story_subclass,
        hit_die_roll_one: 1,
        hit_die_roll_two: 1
      )
      replacement_issue = LevelUpPlanner.new(character, replacement).issues.find do |issue|
        issue.fetch(:message).include?(story_subclass)
      end

      assert_equal "#{story_subclass} is story-based and requires a GM-approved story change, not an ordinary level-up choice.", replacement_issue.fetch(:message)
      assert_equal "Heroes 2.0.1, p. 73", replacement_issue.fetch(:source_ref)
    end
  end

  test "choosing Wild Heart applies its Hit Die and HP feature at level three" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Wild Heart Hero",
      character_class: CharacterClass.find_by!(name: "Hunter"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      skill_set_attributes: { finesse: 7 }
    )
    character.finalize_creation!
    character.update_columns(level: 2, status: "playable")
    character.skill_set.update!(finesse: 8)
    character.trait_set.update!(max_hp: 13, current_hp: 13, max_hit_dice: 2, current_hit_dice: 2)
    level_up = character.level_ups.create!(
      from_level: 2,
      to_level: 3,
      skill_name: "finesse",
      subclass_name: "Wild Heart",
      hit_die_roll_one: 10,
      hit_die_roll_two: 4
    )
    planner = LevelUpPlanner.new(character, level_up)

    assert_equal 10, planner.hit_die_size
    assert_equal "1d10", planner.preview.fetch("traits").fetch("hit_die")
    assert_equal 28, planner.preview.fetch("traits").fetch("max_hp")

    LevelUpService.finalize!(level_up)

    assert_equal "Wild Heart", character.reload.subclass_name
    assert_equal "1d10", character.trait_set.hit_die
    assert_equal 28, character.trait_set.max_hp
  end

  test "a hit die roll outside the character die is blocked with a source explanation" do
    level_up = @character.level_ups.build(
      from_level: 3,
      to_level: 4,
      skill_name: "might",
      stat_name: "strength",
      feature_choices: legal_feature_choices_for(4),
      hit_die_roll_one: 2,
      hit_die_roll_two: 13
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

  test "unlocking a caster resource starts the new mana track full" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Mana Unlock Hero",
      level: 1,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Draconic", "Primordial" ],
      skill_set_attributes: { arcana: 7 }
    )
    character.finalize_creation!
    level_up = character.level_ups.create!(from_level: 1, to_level: 2, skill_name: "arcana", hit_die_roll_one: 3, hit_die_roll_two: 2)

    LevelUpService.finalize!(level_up)

    tracks = character.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal 8, tracks.fetch("mana").fetch("max")
    assert_equal 8, tracks.fetch("mana").fetch("current")
  end

  test "level-up preview names the class features unlocked at the next level" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Feature Preview Hero",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Draconic", "Primordial" ],
      skill_set_attributes: { arcana: 7 }
    )
    character.finalize_creation!
    character.update_columns(level: 1, status: "playable")
    level_up = character.level_ups.build(from_level: 1, to_level: 2, skill_name: "arcana", hit_die_roll_one: 3, hit_die_roll_two: 2)

    progression = LevelUpPlanner.new(character, level_up).preview.fetch("progression")

    assert_includes progression.fetch("features"), "Mana and Unlock Tier 1 Spells"
    assert_includes progression.fetch("features"), "Talented Researcher"
    assert_empty progression.fetch("subclass_features")
  end

  test "level-up requires the source-defined number of feature choices" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Choice Count Hero",
      level: 1,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      skill_set_attributes: { finesse: 7 }
    )
    character.finalize_creation!

    level_up = character.level_ups.build(
      from_level: 1,
      to_level: 2,
      skill_name: "finesse",
      feature_choices: { "Thrill of the Hunt" => [ "Fleet Feet" ] },
      hit_die_roll_one: 4,
      hit_die_roll_two: 2
    )

    planner = LevelUpPlanner.new(character, level_up)

    assert_not planner.valid?
    assert_includes planner.explanations.map { |explanation| explanation[:message] }, "Choose 2 Thrill of the Hunt options at level 2."
    assert_equal 2, planner.feature_choice_pools.first.fetch("count")
    assert_equal [ "Fleet Feet" ], planner.preview.fetch("feature_choices").fetch("Thrill of the Hunt")
  end

  test "legal feature choices persist on the character and revision" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Choice Ledger Hero",
      level: 1,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      skill_set_attributes: { finesse: 7 }
    )
    character.finalize_creation!
    level_up = character.level_ups.create!(
      from_level: 1,
      to_level: 2,
      skill_name: "finesse",
      feature_choices: { "Thrill of the Hunt" => [ "Fleet Feet", "Wild Instinct" ] },
      hit_die_roll_one: 4,
      hit_die_roll_two: 2
    )

    LevelUpService.finalize!(level_up)
    character.reload

    assert_equal [ "Fleet Feet", "Wild Instinct" ], character.recorded_feature_choices.fetch("Thrill of the Hunt")
    assert_equal [ "Fleet Feet", "Wild Instinct" ], character.feature_choice_ledger.fetch("Thrill of the Hunt").fetch("2")
    assert_equal [ "Fleet Feet", "Wild Instinct" ], character.snapshot_payload.fetch("progression").fetch("feature_choices").first.fetch(:selected)
    assert_equal [ "Fleet Feet", "Wild Instinct" ], level_up.reload.preview.fetch("feature_choices").fetch("Thrill of the Hunt")
  end

  # S-02:AC-1 S-06:AC-1 S-06:AC-2 S-06:AC-5
  test "Shadowmancer level-ups require and persist feature-granted and newly earned languages" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Language Progression Hero",
      level: 1,
      character_class: CharacterClass.find_by!(name: "Shadowmancer"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Draconic", "Primordial" ]
    )
    character.skill_set.update!(arcana: character.skill_initial_value("arcana") + 4)
    character.finalize_creation!

    level_two = character.level_ups.create!(
      from_level: 1,
      to_level: 2,
      skill_name: "arcana",
      hit_die_roll_one: 3,
      hit_die_roll_two: 2
    )
    LevelUpService.finalize!(level_two)

    level_three = character.level_ups.create!(
      from_level: 2,
      to_level: 3,
      skill_name: "arcana",
      subclass_name: "Pact of the Red Dragon",
      feature_choices: { "Lesser Shadow Invocation" => [ "Devoted Acolyte" ] },
      hit_die_roll_one: 3,
      hit_die_roll_two: 2
    )
    planner = LevelUpPlanner.new(character, level_three)

    assert_not planner.valid?
    feature_language_issue = planner.issues.find { |issue| issue.fetch(:message).include?("Devoted Acolyte") }
    assert_equal "Choose 2 more languages for Devoted Acolyte.", feature_language_issue.fetch(:message)
    assert_equal "Heroes 2.0.1, p. 46", feature_language_issue.fetch(:source_ref)

    level_three.update!(feature_language_choices: { "Devoted Acolyte" => [ "Celestial", "Deep Speak" ] })
    planner = LevelUpPlanner.new(character, level_three)
    assert planner.valid?, planner.explanations.map { |explanation| explanation.fetch(:message) }.join(" | ")
    assert_includes planner.preview.fetch("languages"), "Celestial"
    assert_includes planner.preview.fetch("languages"), "Deep Speak"
    LevelUpService.finalize!(level_three)

    character.reload
    assert_equal [ "Celestial", "Deep Speak" ], character.feature_language_choices.fetch("Devoted Acolyte")
    assert_includes character.known_language_names, "Celestial"
    assert_includes character.known_language_names, "Deep Speak"

    level_four_without_language = character.level_ups.create!(
      from_level: 3,
      to_level: 4,
      skill_name: "arcana",
      stat_name: "intelligence",
      feature_choices: { "Greater Shadow Invocation" => [ "Shadow Magus" ] },
      hit_die_roll_one: 3,
      hit_die_roll_two: 2
    )
    planner = LevelUpPlanner.new(character, level_four_without_language)
    int_language_issue = planner.issues.find { |issue| issue.fetch(:message).include?("your INT") }
    assert_equal "Choose 1 more language for your INT.", int_language_issue.fetch(:message)

    level_four_without_language.update!(language_choices: [ "Elvish" ])
    planner = LevelUpPlanner.new(character, level_four_without_language)
    assert planner.valid?, planner.explanations.map { |explanation| explanation.fetch(:message) }.join(" | ")
    assert_includes planner.preview.fetch("languages"), "Elvish"
    LevelUpService.finalize!(level_four_without_language)

    character.reload
    assert_equal [ "Draconic", "Primordial", "Elvish" ], character.language_choices
    assert_includes character.known_language_names, "Elvish"
  end

  test "Commander combat abilities cannot repeat earlier orders or tactics" do
    character = commander_at_level_five
    options_planner = LevelUpPlanner.new(
      character,
      character.level_ups.build(from_level: 5, to_level: 6, skill_name: "lore", hit_die_roll_one: 4, hit_die_roll_two: 2)
    )
    pool = options_planner.feature_choice_pools.find { |choice_pool| choice_pool.fetch("name") == "Combat Ability" }

    assert_not_includes pool.fetch("options"), "Face Me!"
    assert_not_includes pool.fetch("options"), "Heavy Strike"
    assert_includes pool.fetch("options"), "+1 max Combat Dice"

    level_up = character.level_ups.build(
      from_level: 5,
      to_level: 6,
      skill_name: "lore",
      feature_choices: { "Combat Ability" => [ "Face Me!" ] },
      hit_die_roll_one: 4,
      hit_die_roll_two: 2
    )
    planner = LevelUpPlanner.new(character, level_up)

    assert_not planner.valid?
    issue = planner.issues.find { |item| item[:message].include?("already been selected from another Commander ability list") }
    assert_equal "Heroes 2.0.1, pp. 20, 22", issue.fetch(:source_ref)
    assert_equal "Choose another Combat Ability or gain +1 max Combat Dice.", issue.fetch(:quote)
  end

  # S-02:AC-1 S-02:AC-2 S-06:AC-2 S-06:AC-4 S-09:AC-3
  test "cross-pool duplicate validation uses generic catalog rules for any class" do
    original_catalog = Rules::NimbleCatalog.data
    changed_catalog = original_catalog.deep_dup
    berserker_pools = changed_catalog.fetch("choice_pools").fetch("Berserker")
    berserker_pools["Test Historical Talent"] = {
      "source_ref" => "Test rules, p. 99",
      "choices" => { 2 => 1 },
      "options" => [ "Shared Test Talent" ]
    }
    berserker_pools["Test Current Talent"] = {
      "source_ref" => "Test rules, p. 100",
      "source_quote" => "Choose a new talent from this list.",
      "unique_across_pools" => [ "Test Historical Talent", "Test Current Talent" ],
      "unique_across_pools_label" => "test talent list",
      "unique_across_pools_source_quote" => "Choose another distinct talent.",
      "choices" => { 4 => 1 },
      "options" => [ "Shared Test Talent", "Different Test Talent" ]
    }
    Rules::NimbleCatalog.instance_variable_set(:@data, changed_catalog)

    begin
      @character.update_columns(feature_choices: {
        "Test Historical Talent" => { "2" => [ "Shared Test Talent" ] }
      })
      level_up = @character.level_ups.build(
        from_level: 3,
        to_level: 4,
        skill_name: "might",
        stat_name: "strength",
        feature_choices: {
          "Savage Arsenal" => [ "Death Blow" ],
          "Test Current Talent" => [ "Shared Test Talent" ]
        },
        hit_die_roll_one: 2,
        hit_die_roll_two: 8
      )
      planner = LevelUpPlanner.new(@character, level_up)
      issue = planner.issues.find do |item|
        item[:message] == "Shared Test Talent has already been selected from another test talent list."
      end

      assert issue, planner.issues.map { |item| item.fetch(:message) }.join(" | ")
      assert_equal "Test rules, p. 100", issue.fetch(:source_ref)
      assert_equal "Choose another distinct talent.", issue.fetch(:quote)
    ensure
      Rules::NimbleCatalog.instance_variable_set(:@data, original_catalog)
    end
  end

  # S-02:AC-1 S-02:AC-2 S-06:AC-2 S-08:AC-4 S-09:AC-3
  test "Spellblade level-ups replace tactics and mastery with distinct order-or-spell choices" do
    character = commander_at_level_five
    already_known = Spell.where(tier: 0..1).first!
    new_spell = Spell.where(tier: 0..1).where.not(name: already_known.name).first!
    character.update_columns(
      subclass_name: "Spellblade",
      feature_choices: {
        "Commander's Orders" => { "2" => [ "Face Me!", "Hold the Line!" ] },
        "Arcane Command" => { "4" => [ "Spell: #{already_known.name}" ] }
      }
    )

    level_up = character.level_ups.create!(
      from_level: 5,
      to_level: 6,
      skill_name: "lore",
      feature_choices: {
        "Arcane Command" => [ "Order: I Can Do This ALL DAY!" ],
        "Combat Ability" => [ "Spell: #{new_spell.name}" ]
      },
      hit_die_roll_one: 4,
      hit_die_roll_two: 2
    )
    planner = LevelUpPlanner.new(character, level_up)
    pools = planner.feature_choice_pools.index_by { |pool| pool.fetch("name") }

    assert_not_includes pools.keys, "Combat Tactics"
    assert_not_includes pools.keys, "Weapon Mastery"
    assert_includes pools.fetch("Arcane Command").fetch("options"), "Order: I Can Do This ALL DAY!"
    assert_includes pools.fetch("Combat Ability").fetch("options"), "Spell: #{new_spell.name}"
    assert_not_includes pools.fetch("Combat Ability").fetch("options"), "Spell: #{already_known.name}"
    assert_not_includes pools.fetch("Combat Ability").fetch("options"), "Heavy Strike"
    assert_includes pools.fetch("Combat Ability").fetch("options"), "+1 max Combat Dice"
    assert planner.valid?, planner.explanations.map { |explanation| explanation.fetch(:message) }.join(" | ")

    LevelUpService.finalize!(level_up)
    character.reload
    assert_includes character.recorded_feature_choices.fetch("Combat Ability"), "Spell: #{new_spell.name}"
    assert_includes character.sheet_spells.pluck(:name), new_spell.name
    assert new_spell.available_to?(character)
  end

  # S-02:AC-1 S-02:AC-2 S-06:AC-2 S-08:AC-4 S-09:AC-3
  test "Spellblade level-up validation rejects duplicate arcane spell picks" do
    character = commander_at_level_five
    character.update_columns(
      subclass_name: "Spellblade",
      feature_choices: {
        "Commander's Orders" => { "2" => [ "Face Me!", "Hold the Line!" ] }
      }
    )
    duplicated_spell = Spell.where(tier: 0..1).first!
    level_up = character.level_ups.build(
      from_level: 5,
      to_level: 6,
      skill_name: "lore",
      feature_choices: {
        "Arcane Command" => [ "Spell: #{duplicated_spell.name}" ],
        "Combat Ability" => [ "Spell: #{duplicated_spell.name}" ]
      },
      hit_die_roll_one: 4,
      hit_die_roll_two: 2
    )

    planner = LevelUpPlanner.new(character, level_up)

    assert_not planner.valid?
    assert planner.issues.any? { |issue| issue.fetch(:message).include?("Choose a different spell") }
  end

  # S-02:AC-1 S-02:AC-2 S-06:AC-2 S-08:AC-4 S-09:AC-3
  test "Spellblade cannot select a Commander’s Order it already knows" do
    character = commander_at_level_five
    character.update_columns(
      subclass_name: "Spellblade",
      feature_choices: {
        "Commander's Orders" => { "2" => [ "Face Me!", "Hold the Line!" ] }
      }
    )
    level_up = character.level_ups.build(
      from_level: 5,
      to_level: 6,
      skill_name: "lore",
      feature_choices: {
        "Arcane Command" => [ "Order: Face Me!" ],
        "Combat Ability" => [ "+1 max Combat Dice" ]
      },
      hit_die_roll_one: 4,
      hit_die_roll_two: 2
    )

    planner = LevelUpPlanner.new(character, level_up)

    assert_includes planner.feature_choice_pools.find { |pool| pool.fetch("name") == "Arcane Command" }.fetch("options"), "Order: Face Me!"
    assert_not planner.valid?
    assert planner.issues.any? { |issue| issue.fetch(:message).include?("Choose a different Commander’s Order") }
  end

  test "repeated Commander Combat Dice upgrades increase and preserve the resource maximum" do
    character = commander_at_level_five
    original_max = character.trait_set.resource_tracks.find { |track| track.fetch("key") == "combat_dice" }.fetch("max")
    level_six = character.level_ups.create!(
      from_level: 5,
      to_level: 6,
      skill_name: "lore",
      feature_choices: {
        "Combat Ability" => [ "+1 max Combat Dice" ],
        "Weapon Mastery" => [ "Slashing" ]
      },
      hit_die_roll_one: 4,
      hit_die_roll_two: 2
    )

    assert_equal original_max + 1, LevelUpPlanner.new(character, level_six).preview.fetch("traits").fetch("max_resource")
    LevelUpService.finalize!(level_six)
    character.reload
    assert_equal original_max + 1, character.trait_set.resource_tracks.find { |track| track.fetch("key") == "combat_dice" }.fetch("max")

    level_seven = character.level_ups.create!(from_level: 6, to_level: 7, skill_name: "lore", hit_die_roll_one: 4, hit_die_roll_two: 2)
    LevelUpService.finalize!(level_seven)
    character.reload

    level_eight = character.level_ups.create!(
      from_level: 7,
      to_level: 8,
      skill_name: "lore",
      stat_name: "intelligence",
      language_choices: [ "Deep Speak" ],
      feature_choices: { "Combat Ability" => [ "+1 max Combat Dice" ] },
      hit_die_roll_one: 4,
      hit_die_roll_two: 2
    )
    planner = LevelUpPlanner.new(character, level_eight)

    assert planner.valid?, planner.explanations.map { |explanation| explanation[:message] }.join(" | ")
    assert_equal original_max + 2, planner.preview.fetch("traits").fetch("max_resource")
    LevelUpService.finalize!(level_eight)

    character.reload
    combat_dice = character.trait_set.resource_tracks.find { |track| track.fetch("key") == "combat_dice" }
    assert_equal original_max + 2, combat_dice.fetch("max")
    assert_equal [ "+1 max Combat Dice", "+1 max Combat Dice" ], character.recorded_feature_choices.fetch("Combat Ability")
  end

  test "Vanguard level-eleven feature raises the Commander Combat Dice maximum" do
    character = commander_at_level_five
    stats = Character::STAT_NAMES.index_with { |stat| character.stat_value(stat) }

    bulwark_max = character.derived_resource_tracks_for(
      stat_values: stats,
      level: 11,
      subclass_name: "Champion of the Bulwark"
    ).find { |track| track.fetch("key") == "combat_dice" }.fetch("max")
    vanguard_max = character.derived_resource_tracks_for(
      stat_values: stats,
      level: 11,
      subclass_name: "Champion of the Vanguard"
    ).find { |track| track.fetch("key") == "combat_dice" }.fetch("max")

    assert_equal bulwark_max + 1, vanguard_max
    assert_equal "Heroes 2.0.1, p. 23", character.derived_feature_effects(
      level: 11,
      subclass_name: "Champion of the Vanguard"
    ).fetch("source_ref")
  end

  test "illegal feature options and prerequisites are blocked with source explanations" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Choice Rules Hero",
      level: 1,
      character_class: CharacterClass.find_by!(name: "The Cheat"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Draconic", "Primordial" ],
      skill_set_attributes: { finesse: 7 }
    )
    character.finalize_creation!
    character.update_columns(level: 3, status: "playable")

    level_up = character.level_ups.build(
      from_level: 3,
      to_level: 4,
      skill_name: "finesse",
      feature_choices: { "Underhanded Ability" => [ "Sunder Armor (Heavy)" ] },
      hit_die_roll_one: 3,
      hit_die_roll_two: 2
    )

    planner = LevelUpPlanner.new(character, level_up)
    messages = planner.explanations.map { |explanation| explanation[:message] }

    assert_not planner.valid?
    assert_includes messages, "Sunder Armor (Heavy) requires Sunder Armor (Medium) first."
    assert_equal "Heroes 2.0.1, p. 16", planner.issues.find { |issue| issue[:message].include?("requires") }.fetch(:source_ref)
  end

  test "Mage utility-school choices are required, source-validated, and persisted" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Utility Choice Hero",
      level: 1,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Draconic", "Primordial" ],
      skill_set_attributes: { arcana: 7 }
    )
    character.finalize_creation!
    character.update_columns(level: 2, status: "playable")
    character.skill_set.update!(arcana: 8)

    level_up = character.level_ups.create!(
      from_level: 2,
      to_level: 3,
      skill_name: "arcana",
      subclass_name: "Chaos",
      spell_choices: { "Elemental Mastery" => [ "Fire" ] },
      hit_die_roll_one: 3,
      hit_die_roll_two: 2
    )
    planner = LevelUpPlanner.new(character, level_up)

    assert planner.valid?, planner.explanations.map { |explanation| explanation[:message] }.join(" | ")
    assert_equal [ "Fire", "Ice", "Lightning" ], planner.spell_choice_pools.first.fetch("options")

    LevelUpService.finalize!(level_up)
    character.reload

    assert_equal [ "Fire" ], character.spell_choice_ledger.fetch("Elemental Mastery").fetch("3")
    assert character.spells.exists?(name: "Firebrand")
    assert_not character.spells.exists?(name: "Ice Disk")
    assert_includes character.snapshot_payload.fetch("progression").fetch("spell_choices").first.fetch(:selected), "Fire"
  end

  test "utility spell choices are blocked when the source pool is incomplete" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Missing Utility Choice Hero",
      level: 1,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Draconic", "Primordial" ],
      skill_set_attributes: { arcana: 7 }
    )
    character.finalize_creation!
    character.update_columns(level: 2, status: "playable")
    character.skill_set.update!(arcana: 8)
    level_up = character.level_ups.build(from_level: 2, to_level: 3, skill_name: "arcana", subclass_name: "Chaos", hit_die_roll_one: 3, hit_die_roll_two: 2)

    planner = LevelUpPlanner.new(character, level_up)

    assert_not planner.valid?
    issue = planner.issues.find { |item| item[:message].include?("Elemental Mastery") }
    assert_equal "Heroes 2.0.1, p. 33", issue.fetch(:source_ref)
    assert_includes issue.fetch(:message), "Choose 1 Elemental Mastery option"
  end

  private
    def legal_feature_choices_for(level)
      @character.feature_choice_pools_for(level).to_h do |pool|
        [ pool.fetch("name"), Array(pool.fetch("options")).first(pool.fetch("count").to_i) ]
      end
    end

    def commander_at_level_five
      Rails.application.load_seed unless CharacterClass.exists?(name: "Commander")
      character = Character.create!(
        name: "Commander Dice Hero",
        level: 1,
        character_class: CharacterClass.find_by!(name: "Commander"),
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        stat_array: "standard",
        language_choices: [ "Draconic", "Primordial" ],
        skill_set_attributes: { might: 7 }
      )
      character.finalize_creation!
      character.update_columns(level: 5, status: "playable", subclass_name: "Champion of the Bulwark")
      character.skill_set.update!(might: character.skill_initial_value("might") + 8)
      character.update!(feature_choices: {
        "Commander's Orders" => { "2" => [ "Face Me!", "Hold the Line!" ] },
        "Combat Tactics" => { "4" => [ "Heavy Strike" ] }
      })
      stat_values = Character::STAT_NAMES.index_with { |stat| character.stat_value(stat) }
      resources = character.derived_resource_values_for(stat_values: stat_values, level: 5)
      legacy_values = character.resource_tracker_values_for(resources.fetch(:resource_tracks))
      character.trait_set.update!(
        resource_name: resources.fetch(:name),
        resource_formula: resources.fetch(:formula),
        resource_die: resources.fetch(:die),
        max_resource: legacy_values.fetch(:max_resource),
        current_resource: legacy_values.fetch(:current_resource),
        resource_tracks: resources.fetch(:resource_tracks)
      )
      character
    end
end
