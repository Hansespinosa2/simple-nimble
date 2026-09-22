require "test_helper"

# S-06:AC-8 S-09:AC-1 S-09:AC-2 S-09:AC-3 S-09:AC-4 S-09:AC-5
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
        ruleset_version: @ruleset
      )
      character.finalize_creation!

      skill = Character::SKILL_TO_STAT.find { |_name, stat| character_class.key_stats.include?(stat) }.first
      level_up = character.level_ups.create!(from_level: 1, to_level: 2, skill_name: skill)
      LevelUpService.finalize!(level_up)

      assert_equal 2, character.reload.level, "#{class_name} should level up through the golden path"
      assert character.playable?, "#{class_name} should remain playable after level-up"
      assert level_up.reload.finalized?, "#{class_name} should record a finalized transition"
    end
  end
end
