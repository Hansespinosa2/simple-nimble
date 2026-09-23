require "test_helper"

class TraitSetTest < ActiveSupport::TestCase
  # S-03:AC-2 S-05:AC-2 S-06:AC-3
  test "persists the mutable in-game values separately from the character" do
    character = Character.create!(name: "Trait Tester")
    character.trait_set.update!(current_hp: 4, temp_hp: 2, current_wounds: 1, current_actions: 2)

    traits = character.reload.trait_set
    assert_equal character, traits.character
    assert_equal 4, traits.current_hp
    assert_equal 2, traits.temp_hp
    assert_equal 1, traits.current_wounds
    assert_equal 2, traits.current_actions
  end

  test "rejects impossible tracker values on the server" do
    character = Character.create!(name: "Bounded Tracker")
    traits = character.trait_set
    traits.assign_attributes(
      current_hp: -1,
      temp_hp: -1,
      current_wounds: traits.max_wounds + 1,
      current_actions: traits.max_actions + 1,
      current_hit_dice: traits.max_hit_dice + 1
    )

    assert_not traits.valid?
    assert_includes traits.errors[:current_hp], "must be greater than or equal to 0"
    assert_includes traits.errors[:temp_hp], "must be greater than or equal to 0"
    assert_includes traits.errors[:current_wounds], "cannot exceed max wounds"
    assert_includes traits.errors[:current_actions], "cannot exceed max actions"
    assert_includes traits.errors[:current_hit_dice], "cannot exceed max hit dice"
  end
end
