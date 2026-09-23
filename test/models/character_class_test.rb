require "test_helper"

class CharacterClassTest < ActiveSupport::TestCase
  # S-02:AC-1 S-05:AC-6 S-06:AC-2
  test "exposes key and secondary stats as structured progression data" do
    character_class = CharacterClass.create!(
      name: "Test Commander",
      key_stat_one: "strength",
      key_stat_two: "intelligence",
      hit_die: "1d10",
      starting_hp: 17,
      save_bonus_stat: "strength",
      save_penalty_stat: "dexterity"
    )

    assert_equal %w[strength intelligence], character_class.key_stats
    assert_equal %w[dexterity will], character_class.secondary_stats
  end

  test "rejects duplicate key stats and unknown save stats" do
    duplicate = CharacterClass.new(
      name: "Duplicate Keys",
      key_stat_one: "strength",
      key_stat_two: "strength",
      hit_die: "1d8",
      starting_hp: 12,
      save_bonus_stat: "luck",
      save_penalty_stat: "will"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key_stat_two], "must be different from the first key stat"
    assert_includes duplicate.errors[:save_bonus_stat], "is not included in the list"
  end
end
