require "test_helper"

class StatSetTest < ActiveSupport::TestCase
  # S-02:AC-1 S-03:AC-2 S-05:AC-2
  test "belongs to the character whose stats it represents" do
    character = Character.create!(name: "Stat Tester")
    character.stat_set.update!(strength: 3, dexterity: 1, intelligence: 0, will: -1)

    assert_equal character, character.stat_set.reload.character
    assert_equal [ 3, 1, 0, -1 ], Character::STAT_NAMES.map { |stat| character.stat_set.public_send(stat) }
  end
end
