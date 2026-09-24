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

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "condition tracking distinguishes manual conditions, derived states, and minor statuses" do
    conditions = @catalog.condition_tracking
    expected_manual = %w[
      Blinded Charmed Dazed Frightened Grappled Hampered Incapacitated Invisible Petrified
      Poisoned Prone Restrained Riding Slowed Taunted
    ]
    expected_derived = %w[Bloodied Dying Wounded]

    assert_equal "Core Rules 2.0.1, p. 11", conditions.fetch("source_ref")
    assert_equal expected_manual, conditions.fetch("manual_conditions")
    assert_equal expected_derived, conditions.fetch("derived_conditions").map { |entry| entry.fetch("name") }
    assert_equal 18, expected_manual.length + expected_derived.length
    assert_equal %w[Charged Distracted Smoldering], conditions.fetch("minor_status_examples")
    assert_match(/does not apply their effects or durations/, conditions.fetch("tracker_note"))
  end

  test "the starting-gold alternative and coin slot size are source-backed" do
    starting_equipment = @catalog.starting_equipment_rules

    assert_equal "Core Rules 2.0.1, p. 20", starting_equipment.fetch("source_ref")
    assert_equal 50, starting_equipment.fetch("gold_per_level")
    assert_equal 500, starting_equipment.fetch("gold_per_inventory_slot")
    assert_equal true, starting_equipment.fetch("gold_scales_with_starting_level")
    assert_equal "Core Rules 2.0.1, p. 21", starting_equipment.fetch("gold_per_inventory_slot_source_ref")
    assert_includes starting_equipment.fetch("gold_per_level_source_quote"), "multiply that by the level"
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-1 S-05:AC-2 S-09:AC-3
  test "background starting gear remains explicitly unitemized rather than being invented" do
    starting_equipment = @catalog.starting_equipment_rules

    assert_equal "not_itemized_in_parsed_sources", starting_equipment.fetch("background_gear_status")
    assert_equal "Core Rules 2.0.1, p. 20", starting_equipment.fetch("background_gear_source_ref")
    assert_includes starting_equipment.fetch("background_gear_source_quote"), "class and background"
    assert_match(/do not itemize gear by background/, starting_equipment.fetch("background_gear_note"))
  end

  test "class entries expose equipment and resource data used by the sheet" do
    mage = CharacterClass.find_by!(name: "Mage")

    assert_includes mage.starting_gear, "Staff"
    assert_equal [ "cloth" ], mage.armor_proficiencies
    assert_includes mage.weapon_proficiencies, "wands"
    assert_equal "INT * 3 + LVL", mage.resource_rules.fetch("max_formula")
    assert_equal({ "unarmored_formula" => "dexterity", "source_ref" => "Core Rules 2.0.1, p. 33" }, mage.armor_rules)
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2
  test "all class armor proficiencies match the Heroes class entries" do
    expected = {
      "Berserker" => [],
      "The Cheat" => [ "leather" ],
      "Commander" => [ "mail", "shields" ],
      "Hunter" => [ "leather" ],
      "Mage" => [ "cloth" ],
      "Oathsworn" => [ "all" ],
      "Shadowmancer" => [ "cloth" ],
      "Shepherd" => [ "mail", "shields" ],
      "Songweaver" => [ "cloth", "leather" ],
      "Stormshifter" => [ "cloth", "leather" ],
      "Zephyr" => []
    }

    expected.each do |class_name, proficiencies|
      assert_equal proficiencies, @catalog.class_for(class_name).fetch("armor_proficiencies"), "#{class_name} armor proficiency"
    end
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2
  test "Zephyr's level-thirteen Armor feature retains its specific source" do
    assert_nil @catalog.derived_effects_for("Zephyr", nil, 12)["armor_multiplier"]
    effects = @catalog.derived_effects_for("Zephyr", nil, 13)

    assert_equal 2, effects.fetch("armor_multiplier")
    assert_equal "Heroes 2.0.1, p. 68", effects.fetch("armor_multiplier_source_ref")
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "the armor catalog matches the published armor, shield, slot, cost, and requirement table" do
    expected = {
      "Adventurer's Garb" => [ "armor", "cloth", 2, "dexterity", nil, nil, 10 ],
      "Minor Enchantment" => [ "armor", "cloth", 3, "dexterity", nil, nil, 100 ],
      "Major Enchantment" => [ "armor", "cloth", 4, "dexterity", nil, nil, 1_000 ],
      "Epic Enchantment" => [ "armor", "cloth", 5, "dexterity", nil, nil, 10_000 ],
      "Cheap Hides" => [ "armor", "leather", 3, "dexterity", nil, nil, 5 ],
      "Ox Hide" => [ "armor", "leather", 4, "dexterity", nil, nil, 45 ],
      "Hard Leather" => [ "armor", "leather", 5, "dexterity", nil, 1, 300 ],
      "Wyrmhide" => [ "armor", "leather", 6, "dexterity", nil, 1, 2_000 ],
      "Rusty Mail" => [ "armor", "mail", 6, "dexterity", 2, nil, 15 ],
      "Chain Shirt" => [ "armor", "mail", 9, "dexterity", 2, 2, 60 ],
      "Scale Mail" => [ "armor", "mail", 12, "dexterity", 2, 3, 700 ],
      "Dragonscale" => [ "armor", "mail", 15, "dexterity", 2, 4, 3_000 ],
      "Rusty Plate" => [ "armor", "plate", 10, "flat", nil, 2, 25 ],
      "Half Plate" => [ "armor", "plate", 14, "flat", nil, 3, 200 ],
      "Full Plate" => [ "armor", "plate", 18, "flat", nil, 4, 2_000 ],
      "Mithril Plate" => [ "armor", "plate", 22, "flat", nil, 5, 5_000 ],
      "Wooden Buckler" => [ "shield", "shields", 2, "flat", nil, nil, 5 ],
      "Iron Shield" => [ "shield", "shields", 4, "flat", nil, 2, 80 ],
      "Tower Shield" => [ "shield", "shields", 6, "flat", nil, 3, 1_500 ],
      "Dragon Shield" => [ "shield", "shields", 8, "flat", nil, 3, 9_000 ]
    }

    catalog = @catalog.equipment_armor_items
    assert_equal expected.keys.sort, catalog.keys.sort
    expected.each do |name, (kind, proficiency, armor, formula, dexterity_cap, strength_requirement, cost)|
      item = catalog.fetch(name)
      assert_equal kind, item.fetch("kind"), name
      assert_equal proficiency, item.fetch("proficiency"), name
      assert_equal armor, item.fetch("armor_value"), name
      assert_equal formula, item.fetch("formula"), name
      dexterity_cap ? assert_equal(dexterity_cap, item["dexterity_cap"], name) : assert_nil(item["dexterity_cap"], name)
      strength_requirement ? assert_equal(strength_requirement, item["strength_requirement"], name) : assert_nil(item["strength_requirement"], name)
      assert_equal cost, item.fetch("cost_gp"), name
      assert_equal 1, item.fetch("slots_worn"), name
      assert_equal(kind == "shield" ? 1 : 2, item.fetch("slots_unworn"), name)
      assert_equal "Core Rules 2.0.1, p. 33", item.fetch("source_ref"), name
    end
    assert_equal "Core Rules 2.0.1, p. 21", @catalog.data.fetch("equipment_armor").fetch("slots_source_ref")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "starting gear for all classes matches Heroes 2.0.1 class entries" do
    expected_gear = {
      "Berserker" => [ "Battleaxe", "Rations (meat)", "Rope (50 ft.)" ],
      "The Cheat" => [ "2 Daggers", "Sling", "Cheap Hides", "Chalk" ],
      "Commander" => [ "Short Sword", "Javelins", "Rusty Mail" ],
      "Hunter" => [ "Shortbow", "Cheap Hides", "Dagger", "Hunting Trap" ],
      "Mage" => [ "Adventurer's Garb", "Staff", "Soap" ],
      "Oathsworn" => [ "Mace", "Rusty Mail", "Wooden Buckler", "Manacles" ],
      "Shadowmancer" => [ "Adventurer's Garb", "Sickle", "Shovel" ],
      "Shepherd" => [ "Rusty Mail", "Mace", "Wooden Buckler", "Bell" ],
      "Songweaver" => [ "Adventurer's Garb", "Instrument", "Dagger", "Mirror" ],
      "Stormshifter" => [ "Cheap Hides", "Staff", "Strange Plant" ],
      "Zephyr" => [ "Staff", "Traveling Robes & Sandals" ]
    }

    expected_gear.each do |class_name, gear|
      entry = @catalog.class_for(class_name)
      assert_equal gear, entry.fetch("starting_gear"), "#{class_name} gear should match its Heroes 2.0.1 source entry"
      assert_match(/Heroes 2\.0\.1/, entry.fetch("source_ref"))
      assert_match(/(?:Core Rules 2\.0\.1|Heroes 2\.0\.1), p\./, entry.fetch("armor").fetch("source_ref"))
    end
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-1 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "all class starting kits have source-backed inventory slots" do
    expected_gear = {
      "Berserker" => { "Battleaxe" => 2, "Rations (meat)" => 1, "Rope (50 ft.)" => 1 },
      "The Cheat" => { "2 Daggers" => 2, "Sling" => 2, "Cheap Hides" => 1, "Chalk" => 1 },
      "Commander" => { "Short Sword" => 1, "Javelins" => 1, "Rusty Mail" => 1 },
      "Hunter" => { "Shortbow" => 2, "Cheap Hides" => 1, "Dagger" => 1, "Hunting Trap" => 1 },
      "Mage" => { "Adventurer's Garb" => 1, "Staff" => 2, "Soap" => 1 },
      "Oathsworn" => { "Mace" => 1, "Rusty Mail" => 1, "Wooden Buckler" => 1, "Manacles" => 1 },
      "Shadowmancer" => { "Adventurer's Garb" => 1, "Sickle" => 1, "Shovel" => 1 },
      "Shepherd" => { "Rusty Mail" => 1, "Mace" => 1, "Wooden Buckler" => 1, "Bell" => 1 },
      "Songweaver" => { "Adventurer's Garb" => 1, "Instrument" => 1, "Dagger" => 1, "Mirror" => 1 },
      "Stormshifter" => { "Cheap Hides" => 1, "Staff" => 2, "Strange Plant" => 1 },
      "Zephyr" => { "Staff" => 2, "Traveling Robes & Sandals" => 1 }
    }

    expected_gear.each do |class_name, expected_items|
      items = @catalog.starting_gear_inventory_items(class_name)
      gear_names = @catalog.class_for(class_name).fetch("starting_gear")
      actual_items = items.to_h { |item| [ item.fetch("name"), item.fetch("slots").to_i ] }

      assert_equal gear_names, items.map { |item| item.fetch("name") }, "#{class_name} slot items should cover its full class kit"
      assert_equal expected_items, actual_items, "#{class_name} item slots should match the source rules and documented default"
      assert items.all? { |item| item.fetch("source_ref").present? }, "#{class_name} gear slots should cite their rules"
      assert_match(/Core Rules/, items.first.fetch("source_ref"), "#{class_name} starting gear should surface an inspectable source")
    end

    assert_match(/GM may adjust/, @catalog.data.fetch("starting_gear_inventory").fetch("miscellaneous_item_note"))
  end

  test "feature choice effects add together for repeated source options" do
    effects = @catalog.feature_choice_effects_for(
      "Commander",
      "Combat Ability" => [ "+1 max Combat Dice", "+1 max Combat Dice" ]
    )

    assert_equal({ "resource_max_modifiers" => { "combat_dice" => 2 } }, effects)
  end

  test "Academy Dropout's starting Utility Spell is source-backed" do
    pool = @catalog.background_spell_choice_for("Academy Dropout")

    assert_equal "Core Rules 2.0.1, p. 28", pool.fetch("source_ref")
    assert_equal "utility_spell_any", pool.fetch("kind")
    assert_equal 1, pool.fetch("count")
  end

  test "limited-use ancestry abilities have explicit uses, resets, and source text" do
    pools = %w[Halfling Gnome Bunbun Dragonborn Kobold Orc Changeling Crystalborn Half-Giant Wyrdling]
      .flat_map { |ancestry| @catalog.ancestry_resource_pools_for(ancestry) }

    assert_equal 10, pools.length
    pools.each do |pool|
      assert_equal "1", pool.fetch("max_formula")
      assert_equal 1, pool.fetch("initial_current")
      assert pool.fetch("reset").present?
      assert_match(/Core Rules 2\.0\.1, p\. 2[3-7]/, pool.fetch("source_ref"))
      assert pool.fetch("source_quote").present?
    end
    assert_empty @catalog.ancestry_resource_pools_for("Human")
    assert_equal %w[safe_rest wound_gained], @catalog.ancestry_resource_pools_for("Dragonborn").first.fetch("reset_events")
    assert_equal [ "day_start" ], @catalog.ancestry_resource_pools_for("Changeling").first.fetch("reset_events")
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
