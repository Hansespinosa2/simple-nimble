require "test_helper"

class SpellTest < ActiveSupport::TestCase
  # S-02:AC-1 S-05:AC-6
  test "requires enough structured data to appear in the spell reference" do
    spell = Spell.new(name: "", school: "", tier: -2)

    assert_not spell.valid?
    assert_includes spell.errors[:name], "can't be blank"
    assert_includes spell.errors[:school], "can't be blank"
    assert_includes spell.errors[:tier], "must be greater than or equal to -1"
  end

  test "accepts utility and cantrip tiers" do
    assert Spell.new(name: "Utility", school: "Wind", tier: -1).valid?
    assert Spell.new(name: "Cantrip", school: "Fire", tier: 0).valid?
  end

  test "does not allow duplicate canon names" do
    duplicate = Spell.new(name: spells(:one).name, school: "Fire", tier: 1)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "utility spells require a source-backed class grant" do
    Rails.application.load_seed
    character = Character.create!(
      name: "Utility Spell Hero",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard"
    )
    utility_spell = Spell.find_by!(name: "Firebrand")

    assert utility_spell.utility?
    assert_not utility_spell.available_to?(character)

    character.update!(spell_choices: { "Elemental Mastery" => { "3" => [ "Fire" ] } })

    assert utility_spell.available_to?(character)
    assert_not Spell.find_by!(name: "Ice Disk").available_to?(character)
  end
end
