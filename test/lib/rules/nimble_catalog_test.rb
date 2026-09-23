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
    assert_equal(-1, @catalog.spell_tier_for("Oathsworn", 1))
    assert_equal 1, @catalog.spell_tier_for("Oathsworn", 2)
  end

  test "mana unlocks at the source-defined class level" do
    assert_equal 2, CharacterClass.find_by!(name: "Mage").resource_rules.fetch("max_start_level")
    assert_equal 2, CharacterClass.find_by!(name: "Oathsworn").resource_rules.fetch("max_start_level")
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
    assert_equal({ "formula" => "dexterity", "base" => 2 }, mage.armor_rules)
  end

  test "feature choice effects add together for repeated source options" do
    effects = @catalog.feature_choice_effects_for(
      "Commander",
      "Combat Ability" => [ "+1 max Combat Dice", "+1 max Combat Dice" ]
    )

    assert_equal({ "resource_max_modifiers" => { "combat_dice" => 2 } }, effects)
  end

  test "Commander weapon mastery is a choice at six and ten, not fourteen" do
    assert_includes @catalog.choice_pools_for("Commander", 6).map { |pool| pool.fetch("name") }, "Weapon Mastery"
    assert_includes @catalog.choice_pools_for("Commander", 10).map { |pool| pool.fetch("name") }, "Weapon Mastery"
    assert_not_includes @catalog.choice_pools_for("Commander", 14).map { |pool| pool.fetch("name") }, "Weapon Mastery"
  end

  test "every published class exposes its level-three subclass choices" do
    expected = {
      "Berserker" => [ "Path of the Mountainheart", "Path of the Red Mist" ],
      "The Cheat" => [ "Tools of the Silent Blade", "Tools of the Scoundrel" ],
      "Commander" => [ "Champion of the Bulwark", "Champion of the Vanguard", "Spellblade" ],
      "Hunter" => [ "Shadowpath", "Wild Heart", "Beastmaster" ],
      "Mage" => [ "Chaos", "Control" ],
      "Oathsworn" => [ "Oath of Vengeance", "Oath of Refuge", "Oathbreaker" ],
      "Shadowmancer" => [ "Pact of the Red Dragon", "Pact of the Abyssal Depths", "Reaver" ],
      "Shepherd" => [ "Luminary of Mercy", "Luminary of Malice" ],
      "Songweaver" => [ "Herald of Snark", "Herald of Courage" ],
      "Stormshifter" => [ "Circle of Fang & Claw", "Circle of Sky & Storm" ],
      "Zephyr" => [ "Way of Flame", "Way of Pain" ]
    }

    expected.each do |class_name, subclasses|
      assert_equal subclasses, CharacterClass.find_by!(name: class_name).subclass_options
    end
  end
end
