require "test_helper"

# S-01:AC-1 S-01:AC-2 S-02:AC-6 S-05:AC-6 S-06:AC-8 S-09:AC-1 S-09:AC-2 S-09:AC-3 S-09:AC-4 S-09:AC-5
class RulesCoverageTest < ActiveSupport::TestCase
  CLASS_NAMES = %w[
    Berserker The\ Cheat Commander Hunter Mage Oathsworn Shadowmancer Shepherd Songweaver Stormshifter Zephyr
  ].freeze

  setup do
    Rails.application.load_seed unless CharacterClass.where(name: "Berserker").exists?
    @ruleset = RulesetVersion.active.first
    @ancestry = Ancestry.find_by!(name: "Human")
    @background = Background.find_by!(name: "Fearless")
  end

  # S-05:AC-1 S-05:AC-2 S-06:AC-2 S-06:AC-3 S-06:AC-8 S-09:AC-1 S-09:AC-2 S-09:AC-3
  test "every canon class completes a legal one-level-at-a-time path through level twenty" do
    CLASS_NAMES.each do |class_name|
      character_class = CharacterClass.find_by!(name: class_name)
      character = Character.create!(
        name: "Coverage #{class_name}",
        level: 1,
        character_class: character_class,
        ancestry: @ancestry,
        background: @background,
        stat_array: "standard",
        spell_school_choice: character_class.spell_schools.include?("choice") ? "Fire" : nil,
        ruleset_version: @ruleset
      )
      assign_required_languages(character)
      skill = Character::SKILL_TO_STAT.find { |_name, stat| character_class.key_stats.include?(stat) }.first
      character.skill_set.public_send("#{skill}=", character.skill_initial_value(skill) + 4)
      character.finalize_creation!

      assert character.reload.playable?, "#{class_name} should finalize as a legal level-one character"

      (2..Character::MAX_LEVEL).each do |target_level|
        level_up = character.level_ups.build(from_level: target_level - 1, to_level: target_level)
        if target_level == character_class.subclass_choice_level
          level_up.subclass_name = character.subclass_options.first
        end

        planner = LevelUpPlanner.new(character, level_up)
        choose_feature_options!(character, level_up, planner)
        planner = LevelUpPlanner.new(character, level_up)
        choose_spell_options!(character, level_up, planner)
        choose_stat_increases!(character, level_up, planner)
        planner = LevelUpPlanner.new(character, level_up)
        choose_feature_languages!(level_up, planner)
        choose_intelligence_languages!(character, level_up, planner)
        planner = LevelUpPlanner.new(character, level_up)
        level_up.skill_name = planner.skill_options.first
        level_up.save!

        assert planner.valid?, "#{class_name} level #{target_level} should have a legal transition: #{planner.issues.map { |issue| issue.fetch(:message) }.join('; ')}"
        LevelUpService.finalize!(level_up)
        character.reload

        assert_equal target_level, character.level, "#{class_name} should advance exactly one level"
        assert character.playable?, "#{class_name} should remain playable after level #{target_level}"
        assert level_up.reload.finalized?, "#{class_name} level #{target_level} should record a finalized transition"
        assert_equal target_level, character.trait_set.max_hit_dice, "#{class_name} Hit Dice should track level #{target_level}"
        level_up.preview.fetch("traits").each do |attribute, expected|
          actual = character.trait_set.public_send(attribute)
          message = "#{class_name} level #{target_level} should persist previewed #{attribute}"
          expected.nil? ? assert_nil(actual, message) : assert_equal(expected, actual, message)
        end
      end
    end
  end

  test "every seeded ancestry can create legally and every seeded spell can be attached" do
    canonical_ancestries = Ancestry.where.not(name: "MyString").order(:name)
    canonical_spells = Spell.where.not(name: [ "MyString", "Fixture Flame", "Fixture Frost" ]).order(:tier, :name)

    assert_equal 24, canonical_ancestries.count
    assert_equal 76, canonical_spells.count

    canonical_ancestries.each do |ancestry|
      character = Character.create!(
        name: "Ancestry Coverage #{ancestry.name}",
        level: 1,
        character_class: CharacterClass.find_by!(name: "Mage"),
        ancestry: ancestry,
        background: @background,
        stat_array: "balanced",
        ruleset_version: @ruleset
      )

      assign_required_languages(character)
      character.skill_set.update!(might: character.skill_initial_value("might") + 4)
      assert character.legal_for_creation?, "#{ancestry.name} should produce a legal draft"
      character.finalize_creation!
      assert character.reload.playable?, "#{ancestry.name} should finalize as playable"
    end

    character = Character.create!(
      name: "Spell Coverage",
      level: 1,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced",
      ruleset_version: @ruleset
    )
    character.skill_set.update!(might: character.skill_initial_value("might") + 4)
    character.spells = canonical_spells

    assert_equal canonical_spells.map(&:id), character.reload.spells.order(:tier, :name).pluck(:id)
  end

  private
    def choose_feature_options!(character, level_up, planner)
      selections = {}
      5.times do
        level_up.feature_choices = selections
        pools = planner.feature_choice_pools
        missing = pools.find do |pool|
          selections.fetch(pool.fetch("name"), []).length < pool.fetch("count").to_i
        end
        break unless missing

        pool_name = missing.fetch("name")
        needed = missing.fetch("count").to_i - selections.fetch(pool_name, []).length
        available = Array(missing.fetch("options")) - selections.fetch(pool_name, [])
        raise "No legal #{pool_name} options remain at level #{planner.target_level}." if available.length < needed

        selections[pool_name] = selections.fetch(pool_name, []) + available.first(needed)
      end

      level_up.feature_choices = selections
      planner = LevelUpPlanner.new(character, level_up)
      incomplete = planner.feature_choice_pools.find do |pool|
        level_up.feature_choices.to_h.fetch(pool.fetch("name"), []).length != pool.fetch("count").to_i
      end
      raise "Could not resolve #{incomplete.fetch('name')} at level #{planner.target_level}." if incomplete
    end

    def choose_spell_options!(character, level_up, planner)
      selections = planner.spell_choice_pools.to_h do |pool|
        pool_name = pool.fetch("name")
        needed = pool.fetch("count").to_i
        available = Array(pool.fetch("options")) - character.recorded_spell_choices.fetch(pool_name, [])
        raise "No legal #{pool_name} spells remain at level #{planner.target_level}." if available.length < needed

        [ pool_name, available.first(needed) ]
      end
      level_up.spell_choices = selections
    end

    def choose_stat_increases!(character, level_up, planner)
      count = planner.stat_increase_choice_count
      return if count.zero?

      eligible_stats = planner.stat_options.select do |stat_name|
        character.stat_value(stat_name) + planner.stat_increase_amount <= planner.max_stat_value
      end
      selected_stats = eligible_stats.first(count)
      raise "No legal stat increase remains at level #{planner.target_level}." if selected_stats.length < count

      level_up.stat_name = selected_stats.first
      level_up.second_stat_name = selected_stats.second
    end

    def choose_feature_languages!(level_up, planner)
      selections = level_up.feature_language_choices.to_h.stringify_keys
      selected_features = planner.feature_choice_pools.flat_map do |pool|
        level_up.feature_choices.to_h.fetch(pool.fetch("name"), [])
      end

      planner.feature_language_choice_rules.each do |feature_name, rule|
        next unless selected_features.include?(feature_name)
        next if selections.fetch(feature_name, []).length == rule.fetch("count").to_i

        options = planner.feature_language_choice_options(feature_name) - selections.values.flatten
        needed = rule.fetch("count").to_i
        raise "No legal #{feature_name} languages remain." if options.length < needed

        selections[feature_name] = options.first(needed)
        level_up.feature_language_choices = selections
        planner = LevelUpPlanner.new(level_up.character, level_up)
      end

      level_up.feature_language_choices = selections
    end

    def choose_intelligence_languages!(character, level_up, planner)
      needed = planner.language_choices_needed
      return if needed.zero?

      excluded = Array(character.language_choices) + level_up.feature_language_choices.to_h.values.flatten
      options = planner.language_choice_options - excluded
      raise "Only #{options.length} new languages remain, but #{needed} are required." if options.length < needed

      level_up.language_choices = options.first(needed)
    end

    def assign_required_languages(character)
      count = character.language_choice_count
      return if count.zero?

      character.update!(language_choices: character.language_choice_options_for.first(count))
    end
end
