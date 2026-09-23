require "test_helper"

class CharacterSpellTest < ActiveSupport::TestCase
  # S-02:AC-1 S-05:AC-6
  test "connects a character to a spell through the join model" do
    character = Character.create!(name: "Spell Tester")
    spell = spells(:one)
    CharacterSpell.create!(character:, spell:)

    assert_equal [ spell ], character.reload.spells.to_a
    assert_equal character, spell.reload.character_spells.first.character
  end

  test "does not add the same spell to a character twice" do
    character = Character.create!(name: "Duplicate Spell Tester")
    spell = spells(:one)
    CharacterSpell.create!(character:, spell:)
    duplicate = CharacterSpell.new(character:, spell:)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:spell_id], "has already been taken"
  end
end
