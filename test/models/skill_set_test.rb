require "test_helper"

class SkillSetTest < ActiveSupport::TestCase
  # S-03:AC-2 S-05:AC-2
  test "belongs to a character and persists every named skill" do
    character = Character.create!(name: "Skill Tester")
    skills = Character::SKILL_NAMES.index_with { 4 }
    skill_set = character.skill_set
    skill_set.update!(skills)

    assert_equal character, skill_set.reload.character
    Character::SKILL_NAMES.each { |skill| assert_equal 4, skill_set.public_send(skill) }
  end
end
