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

  test "every canon class has a legal level-one and level-two path" do
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
      feature_choices = character_class.feature_choice_pools_for(2).to_h do |pool|
        [ pool.fetch("name"), pool.fetch("options").first(pool.fetch("count")) ]
      end
      level_up = character.level_ups.create!(from_level: 1, to_level: 2, skill_name: skill, feature_choices: feature_choices)
      LevelUpService.finalize!(level_up)

      assert_equal 2, character.reload.level, "#{class_name} should level up through the golden path"
      assert character.playable?, "#{class_name} should remain playable after level-up"
      assert level_up.reload.finalized?, "#{class_name} should record a finalized transition"
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
    def assign_required_languages(character)
      count = character.language_choice_count
      return if count.zero?

      character.update!(language_choices: character.language_choice_options_for.first(count))
    end
end
