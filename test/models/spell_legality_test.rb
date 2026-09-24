require "test_helper"

# S-02:AC-1 S-02:AC-2 S-05:AC-2 S-05:AC-3 S-05:AC-6 S-07:AC-1 S-07:AC-2
class SpellLegalityTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    @mage = Character.create!(
      name: "Spell Rules Hero",
      level: 1,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced",
      language_choices: [ "Elvish", "Draconic" ],
      skill_set_attributes: { might: 6 }
    )
  end

  test "a caster can select a cantrip from a known school" do
    flame_dart = Spell.find_by!(name: "Flame Dart")

    assert flame_dart.available_to?(@mage)
    @mage.spells << flame_dart
    assert_empty @mage.creation_issues
  end

  test "a caster cannot select a spell above the class tier unlock" do
    ignite = Spell.find_by!(name: "Ignite")

    assert_not ignite.available_to?(@mage)
    @mage.spells << ignite

    issue = @mage.creation_issues.find { |item| item[:message].include?(ignite.name) }
    assert_equal "Core Rules 2.0.1, Spells", issue.fetch(:source_ref)
    assert issue.fetch(:quote).present?
  end

  test "a caster cannot select a spell from an unknown school" do
    razor_wind = Spell.find_by!(name: "Razor Wind")

    assert_not razor_wind.available_to?(@mage)
    @mage.spells << razor_wind

    assert_includes @mage.creation_issues.map { |item| item[:message] }, "Razor Wind is not available to this class at level 1."
  end

  test "class-restricted spells are not silently available to another caster" do
    mockery = Spell.find_by!(name: "Vicious Mockery")

    assert_not mockery.available_to?(@mage)
    @mage.spells << mockery

    assert_includes @mage.creation_issues.map { |item| item[:message] }, "Vicious Mockery is not available to this class at level 1."
  end

  test "source metadata is present on seeded spells" do
    Spell.where.not(name: [ "Fixture Flame", "Fixture Frost", "MyString" ]).find_each do |spell|
      assert_equal "Core Rules 2.0.1, Spells", spell.source_ref
      assert spell.source_quote.present?, spell.name
      assert_equal [ spell.tier, 0 ].max, spell.mana_cost
    end
  end

  test "Oathsworn does not access Radiant spells until level two" do
    oathsworn = Character.create!(
      name: "Oath Rules Hero",
      level: 1,
      character_class: CharacterClass.find_by!(name: "Oathsworn"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    radiant_cantrip = Spell.find_by!(name: "Rebuke")

    assert_equal(-1, oathsworn.character_class.spell_tier_for(1))
    assert_not radiant_cantrip.available_to?(oathsworn)

    oathsworn.update_columns(level: 2)

    assert radiant_cantrip.available_to?(oathsworn)
  end
end
