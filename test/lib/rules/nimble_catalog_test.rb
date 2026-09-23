require "test_helper"

# S-02:AC-1 S-02:AC-2 S-02:AC-3 S-05:AC-6 S-06:AC-2 S-06:AC-8 S-07:AC-2
class NimbleCatalogTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    @catalog = Rules::NimbleCatalog
  end

  test "the catalog contains every published class and source reference" do
    expected = %w[
      Berserker The\ Cheat Commander Hunter Mage Oathsworn Shadowmancer Shepherd Songweaver Stormshifter Zephyr
    ]

    assert_equal expected, @catalog.classes.keys
    @catalog.classes.each_value do |entry|
      assert entry.fetch("source_ref").present?
      assert_equal 2, entry.fetch("key_stats").length
      assert_equal 2, entry.fetch("secondary_stats").length
      assert entry.fetch("starting_hp").positive?
    end
  end

  test "spell unlocks are read from canonical class schedules" do
    assert_equal 0, @catalog.spell_tier_for("Mage", 1)
    assert_equal 1, @catalog.spell_tier_for("Mage", 2)
    assert_equal 2, @catalog.spell_tier_for("Mage", 4)
    assert_equal 9, @catalog.spell_tier_for("Mage", 18)
    assert_equal 2, @catalog.spell_tier_for("Shadowmancer", 5)
    assert_equal 0, @catalog.spell_tier_for("Berserker", 20)
  end

  test "class-specific stat schedules include the level twenty any-two rule" do
    assert_equal "key", @catalog.stat_increase_for("Mage", 4)
    assert_equal "secondary", @catalog.stat_increase_for("Mage", 5)
    assert_equal "any_two", @catalog.stat_increase_for("Mage", 20)
    assert_equal [ "strength", "dexterity", "intelligence", "will" ], CharacterClass.find_by!(name: "Mage").stat_options_for("any_two")
  end

  test "the catalog exposes derived formulas from the source rules" do
    derived = @catalog.derived_values

    assert_equal 6, derived.fetch("base_speed")
    assert_equal 6, derived.fetch("default_max_wounds")
    assert_equal 10, derived.fetch("base_inventory_slots")
    assert_equal "roll Hit Die with advantage", derived.fetch("hp_level_up_formula")
  end

  test "class entries expose equipment and resource data used by the sheet" do
    mage = CharacterClass.find_by!(name: "Mage")

    assert_includes mage.starting_gear, "Staff"
    assert_equal [ "cloth" ], mage.armor_proficiencies
    assert_includes mage.weapon_proficiencies, "wands"
    assert_equal "INT * 3 + LVL", mage.resource_rules.fetch("max_formula")
  end
end
