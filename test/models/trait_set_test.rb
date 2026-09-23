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
end
