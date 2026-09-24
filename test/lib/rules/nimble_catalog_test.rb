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

  test "every page citation used by the catalog fits its registered source range" do
    core_rules = @catalog.source("core_rules")
    heroes = @catalog.source("heroes")
    gamemasters_guide = @catalog.source("gamemasters_guide")

    assert_equal "Core Rules, pp. 6-37, 44-60", core_rules.fetch("reference")
    assert_equal "Heroes, pp. 7-80", heroes.fetch("reference")
    assert_equal "Gamemaster's Guide, pp. 23, 43", gamemasters_guide.fetch("reference")

    source_references = catalog_source_references(@catalog.data)
    assert_includes source_references, "Core Rules 2.0.1, pp. 21, 33-37"
    assert_includes source_references, "Heroes 2.0.1, p. 80"
    assert_includes source_references, "Heroes 2.0.1, p. 78"

    source_references.each do |reference|
      source_key = registered_source_key(reference)
      next unless source_key

      cited_pages = page_numbers(reference)
      registered_pages = page_numbers(@catalog.source(source_key).fetch("reference"))
      uncovered_pages = cited_pages - registered_pages
      assert_empty uncovered_pages, "#{reference} cites pages outside #{@catalog.source(source_key).fetch('reference')}"
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

  # S-02:AC-1 S-02:AC-2 S-05:AC-2
  test "Songweaver's additional spell school choices match its cited class rule" do
    rule = @catalog.spell_school_choice_for("Songweaver")

    assert_equal %w[Fire Ice Lightning Radiant Necrotic], rule.fetch("allowed_schools")
    assert_equal "Heroes 2.0.1, p. 55", rule.fetch("source_ref")
    assert_equal "You know cantrips from the Wind school and 1 other school of your choice.", rule.fetch("source_quote")
    assert_nil @catalog.spell_school_choice_for("Mage")
    assert_equal rule.fetch("allowed_schools"), CharacterClass.find_by!(name: "Songweaver").spell_school_choice_options
  end

  test "mana unlocks at the source-defined class level" do
    assert_equal 2, CharacterClass.find_by!(name: "Mage").resource_rules.fetch("max_start_level")
    assert_equal 2, CharacterClass.find_by!(name: "Oathsworn").resource_rules.fetch("max_start_level")
  end

  test "initiative resource grants follow the unlock level of their published feature" do
    assert_equal 3, @catalog.story_subclass_feature_unlock_level_for("Commander", "Spellblade", "Arcane Command")
    assert_equal 3, @catalog.story_subclass_feature_unlock_level_for("Commander", "Spellblade", "Firebrand")
    assert_nil @catalog.initiative_resource_grant_for("Shadowmancer", "Reaver", 14)
    reaver_grant = @catalog.initiative_resource_grant_for("Shadowmancer", "Reaver", 15)
    assert_equal "I'm the Patron Now!", reaver_grant.fetch("feature_name")
    assert_equal "shadow_minions", reaver_grant.fetch("resource_key")
    assert_equal 2, reaver_grant.fetch("amount")
    assert_equal "Heroes 2.0.1, p. 78", reaver_grant.fetch("source_ref")

    assert_nil @catalog.initiative_resource_grant_for("Commander", "Spellblade", 2)
    spellblade_grant = @catalog.initiative_resource_grant_for("Commander", "Spellblade", 3)
    assert_equal "Arcane Command", spellblade_grant.fetch("feature_name")
    assert_equal "spellblade_initiative_mana", spellblade_grant.fetch("resource_key")
    assert_equal "maximum", spellblade_grant.fetch("amount")
    assert_equal "Heroes 2.0.1, p. 76", spellblade_grant.fetch("source_ref")
  end

  # S-02:AC-1 S-02:AC-2 S-02:AC-4 S-06:AC-2
  test "every published class follows its source-defined stat schedule through the catalog maximum" do
    max_level = @catalog.derived_values.fetch("max_level").to_i
    expected_schedule = {
      "key" => [ 4, 8, 12, 16 ],
      "secondary" => [ 5, 9, 13, 17 ],
      "any_two" => [ max_level ]
    }
    expected_types = expected_schedule.each_with_object({}) do |(type, levels), types|
      levels.each { |level| types[level] = type }
    end
    class_names = %w[
      Berserker The\ Cheat Commander Hunter Mage Oathsworn Shadowmancer Shepherd Songweaver Stormshifter Zephyr
    ]

    class_names.each do |class_name|
      assert_equal expected_schedule, @catalog.class_for(class_name).fetch("stat_increases"), class_name
      (1..max_level).each do |level|
        expected_type = expected_types[level]
        actual_catalog_type = @catalog.stat_increase_for(class_name, level)
        actual_model_type = CharacterClass.find_by!(name: class_name).stat_increase_type_for(level)
        if expected_type.nil?
          assert_nil actual_catalog_type, "#{class_name} at level #{level}"
          assert_nil actual_model_type, "#{class_name} model at level #{level}"
        else
          assert_equal expected_type, actual_catalog_type, "#{class_name} at level #{level}"
          assert_equal expected_type, actual_model_type, "#{class_name} model at level #{level}"
        end
      end
    end

    assert_equal [ "strength", "dexterity", "intelligence", "will" ], CharacterClass.find_by!(name: "Mage").stat_options_for("any_two")
  end

  test "the catalog exposes derived values and the source-backed skill progression" do
    derived = @catalog.derived_values

    assert_equal 6, derived.fetch("base_speed")
    assert_equal 6, derived.fetch("default_max_wounds")
    assert_equal 10, derived.fetch("base_inventory_slots")
    assert_equal "roll Hit Die with advantage", derived.fetch("hp_level_up_formula")
    assert_equal 10, derived.fetch("save_dc_base")
    assert_equal "DEX", derived.fetch("initiative_formula")
    assert_equal "dexterity", @catalog.stat_name_for_abbreviation(derived.fetch("initiative_formula"))
    assert_equal 5, derived.fetch("max_stat")
    assert_equal 12, derived.fetch("max_skill")
    assert_equal 20, derived.fetch("max_level")
    assert_equal "Heroes 2.0.1, class progressions", derived.fetch("max_level_source_ref")
    assert_equal "Each published class progression ends at level 20.", derived.fetch("max_level_source_quote")
    assert_equal "Core Rules 2.0.1, p. 6", derived.fetch("max_stat_source_ref")
    assert_equal "The maximum a hero’s stat can typically go is +5.", derived.fetch("max_stat_source_quote")
    assert_equal "Core Rules 2.0.1, p. 8", derived.fetch("max_skill_source_ref")
    assert_equal "Roll 1d20 and add your skill (the max bonus a skill can ever have is +12).", derived.fetch("max_skill_source_quote")
    assert_equal 4, derived.fetch("skill_points_at_level_one")
    assert_equal 1, derived.fetch("skill_points_per_level")
    assert_equal 1, derived.fetch("skill_point_transfers_per_level")
    assert_equal "Core Rules 2.0.1, p. 21", derived.fetch("skill_point_progression_source_ref")
    assert_equal "More Skilled. Gain 1 skill point. Additionally, you may move 1 point from one skill to another (as long as the skill doesn’t become negative), reflecting your hero’s evolving expertise and priorities.", derived.fetch("skill_point_progression_source_quote")
    assert_match(/explicitly grant 1 skill point and allow an optional 1-point transfer/, derived.fetch("skill_point_progression_note"))
    assert_match(/Songweaver's Jack of All Trades.*Safe Rest/, derived.fetch("skill_point_progression_note"))
    assert_equal({ "choice_count" => 1, "amount" => 1, "distinct" => true, "label" => "Key Stat" }, @catalog.stat_increase_mechanic_for("key"))
    assert_equal({ "choice_count" => 1, "amount" => 1, "distinct" => true, "label" => "Secondary Stat" }, @catalog.stat_increase_mechanic_for("secondary"))
    assert_equal({ "choice_count" => 2, "amount" => 1, "distinct" => true, "label" => "stat" }, @catalog.stat_increase_mechanic_for("any_two"))
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-1 S-06:AC-2
  test "language options and class-feature grants have exact parsed-source rules" do
    languages = @catalog.language_rules

    assert_equal %w[Common Dwarvish Elvish Goblin Infernal], languages.fetch("languages").first(5)
    assert_equal "Thieves' Cant", languages.fetch("languages")[5]
    assert_equal 10, languages.fetch("languages").length
    assert_equal "Core Rules 2.0.1, pp. 20, 23-26", languages.fetch("source_ref")
    assert_equal "All heroes speak Common by default. Each point of INT grants you an additional language known.", languages.fetch("source_quote")
    assert_equal [ "Thieves' Cant" ], @catalog.class_language_grants_for("The Cheat", 3)
    assert_empty @catalog.class_language_grants_for("The Cheat", 2)
    assert_equal [ "Celestial", "Draconic", "Deep Speak", "Infernal", "Primordial" ], @catalog.language_feature_choice("Devoted Acolyte").fetch("options")
    assert_equal 2, @catalog.language_feature_choice("Devoted Acolyte").fetch("count")
    assert_equal "Heroes 2.0.1, p. 46", @catalog.language_feature_choice("Devoted Acolyte").fetch("source_ref")
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

  # S-02:AC-1 S-02:AC-2 S-07:AC-2 S-09:AC-3
  test "resting rules expose source-backed recovery and field-rest parameters" do
    resting = @catalog.resting_rules
    safe_rest = resting.fetch("safe_rest")
    field_rests = resting.fetch("field_rests")
    catch_breath = field_rests.fetch("catch_breath")
    make_camp = field_rests.fetch("make_camp")

    assert_equal "Core Rules 2.0.1, pp. 9, 16", safe_rest.fetch("source_ref")
    assert_equal true, safe_rest.fetch("recover_all_hit_points")
    assert_equal true, safe_rest.fetch("recover_all_hit_dice")
    assert_equal 1, safe_rest.fetch("wounds_healed")
    assert_equal true, safe_rest.fetch("temporary_hit_points_expire")
    assert_equal "Core Rules 2.0.1, p. 9", safe_rest.fetch("temporary_hit_points_source_ref")
    assert_match(/recover all of their HP, Hit Dice.*heal 1 Wound/, safe_rest.fetch("source_quote"))
    assert_equal "They expire after a Safe Rest.", safe_rest.fetch("temporary_hit_points_source_quote")
    assert_equal 10, catch_breath.fetch("minimum_duration")
    assert_equal "minutes", catch_breath.fetch("duration_unit")
    assert_equal "rolled", catch_breath.fetch("hit_die_result")
    assert_equal 1, catch_breath.fetch("hit_dice_per_use")
    assert_equal "strength", catch_breath.fetch("stat_modifier")
    assert_equal "each_hit_die", catch_breath.fetch("stat_modifier_application")
    assert_equal "Core Rules 2.0.1, p. 16", catch_breath.fetch("source_ref")
    assert_includes catch_breath.fetch("source_quote"), "Expend any number of Hit Dice one at a time"
    assert_equal 8, make_camp.fetch("minimum_duration")
    assert_equal true, make_camp.fetch("requires_food_and_sleep")
    assert_equal "maximum", make_camp.fetch("hit_die_result")
    assert_equal "Core Rules 2.0.1, p. 16", make_camp.fetch("source_ref")
    assert_includes make_camp.fetch("source_quote"), "with food and sleep"
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
    penalty = @catalog.equipment_armor_rules.fetch("nonproficient_worn_armor")
    assert_equal 1, penalty.fetch("defend_action_surcharge")
    assert_equal "Core Rules 2.0.1, p. 32", penalty.fetch("source_ref")
    assert_includes penalty.fetch("source_quote"), "1 additional action"
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

  # S-02:AC-1 S-02:AC-2
  test "Spellblade Deep Knowledge features and spell choices follow each printed level" do
    assert_includes @catalog.subclass_features_for("Commander", "Spellblade", 3), "Deep Knowledge (1)"

    expected_tiers = { 3 => 1, 7 => 2, 11 => 3, 15 => 4 }
    expected_tiers.each do |level, max_tier|
      pools = @catalog.story_subclass_spell_choice_pools_for("Commander", "Spellblade", level)
      assert_equal [ "Deep Knowledge · tiered spell", "Deep Knowledge · Utility Spell" ], pools.map { |pool| pool.fetch("name") }
      tiered_pool = pools.first
      utility_pool = pools.last
      assert_equal max_tier, tiered_pool.fetch("max_tier")
      assert_equal level, tiered_pool.fetch("level")
      assert_equal 1, tiered_pool.fetch("count")
      assert_includes tiered_pool.fetch("source_quote"), "tier #{max_tier} (or lower)"
      assert_equal tiered_pool.fetch("source_quote"), utility_pool.fetch("source_quote")
      assert_equal "Heroes 2.0.1, p. 76", tiered_pool.fetch("source_ref")
    end

    assert_empty @catalog.story_subclass_spell_choice_pools_for("Commander", "Champion of the Bulwark", 3)
  end

  # S-02:AC-1 S-02:AC-2 S-08:AC-4
  test "Spellblade replaces earned tactic and weapon choices with source-defined Arcane Command options" do
    arcane_command = @catalog.story_subclass_feature_choice_pools_for("Commander", "Spellblade", 4).sole
    assert_equal "Arcane Command", arcane_command.fetch("name")
    assert_equal "arcane_command_order_or_spell", arcane_command.fetch("kind")
    assert_equal "Heroes 2.0.1, p. 76", arcane_command.fetch("source_ref")
    assert_equal "Whenever you could choose a Combat Tactic or Weapon Mastery, instead choose another Commander’s Order or a tier 1 (or lower) spell from any spell school.", arcane_command.fetch("source_quote")
    assert_equal 0, arcane_command.fetch("spell_min_tier")
    assert_equal 1, arcane_command.fetch("spell_max_tier")
    assert_equal [ "Combat Tactics", "Weapon Mastery" ], arcane_command.fetch("replaces_feature_choice_pools")
    assert_equal [ "Weapon Mastery" ], @catalog.story_subclass_replaced_progression_features_for("Commander", "Spellblade")

    combat_ability = @catalog.story_subclass_feature_choice_pools_for("Commander", "Spellblade", 6).find { |pool| pool.fetch("name") == "Combat Ability" }
    assert_equal [ 6, 8, 10, 12, 16 ], @catalog.story_subclass_feature_choice_pool_rules_for("Commander", "Spellblade").fetch("Combat Ability").fetch("choices").keys
    assert_equal "arcane_command_combat_ability", combat_ability.fetch("kind")
    assert_empty @catalog.story_subclass_feature_choice_pools_for("Commander", "Spellblade", 5)
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Spellblade temporary initiative mana is a source-backed encounter resource" do
    pool = @catalog.story_subclass_resource_pools_for("Commander", "Spellblade").sole

    assert_equal "spellblade_initiative_mana", pool.fetch("key")
    assert_equal "INT", pool.fetch("max_formula")
    assert_equal 0, pool.fetch("minimum_max")
    assert_equal 0, pool.fetch("initial_current")
    assert_equal [ "encounter_end" ], pool.fetch("reset_events")
    assert_equal "Heroes 2.0.1, p. 76", pool.fetch("source_ref")
    assert_empty @catalog.story_subclass_resource_pools_for("Commander", "Champion of the Bulwark")

    firebrand = @catalog.story_subclass_initiative_features_for("Commander", "Spellblade").sole
    assert_equal "Firebrand", firebrand.fetch("name")
    assert_includes firebrand.fetch("effect"), "Enchant Weapon for free"
    assert_equal "Heroes 2.0.1, p. 77", firebrand.fetch("source_ref")

    orders = @catalog.story_subclass_empowered_orders_for("Commander", "Spellblade")
    assert_equal 6, orders.length
    assert_equal "Glimmering Decree", orders.fetch("Face Me!").fetch("arcane_name")
    assert_equal "Rising Phoenix", orders.fetch("I Can Do This ALL DAY!").fetch("arcane_name")
    assert_equal "Heroes 2.0.1, p. 76", orders.fetch("Coordinated Strike!").fetch("source_ref")
  end

  # S-02:AC-1 S-02:AC-2 S-08:AC-4 S-09:AC-3
  test "Reaver rules remove patron casting and expose the Bonescythe and minion limits" do
    assert_equal [ "pilfered_power" ], @catalog.story_subclass_resource_pool_replacements_for("Shadowmancer", "Reaver")
    assert_equal [ "Shadow Blast" ], @catalog.story_subclass_spell_restrictions_for("Shadowmancer", "Reaver")

    weapon = @catalog.story_subclass_weapon_rules_for("Shadowmancer", "Reaver").fetch("Bonescythe")
    assert_equal 2, weapon.fetch("base_damage_dice")
    assert_equal 1, weapon.fetch("additional_dice_per_interval")
    assert_equal 5, weapon.fetch("additional_die_every_levels")
    assert_equal "d12", weapon.fetch("damage_die")
    assert_equal 2, weapon.fetch("reach")
    assert_includes weapon.fetch("source_quote"), weapon.fetch("invocation_carryover_note")
    assert_equal "Heroes 2.0.1, p. 78", weapon.fetch("source_ref")

    notes = @catalog.story_subclass_feature_notes_for("Shadowmancer", "Reaver")
    assert_equal [ "Hollow One", "Shadow Exploit", "Martyr Spawn", "Grim Harrow", "Reap", "My Blood, My Power", "Otherworldly Might", "I'm the Patron Now!" ], notes.map { |note| note.fetch("name") }
    shadow_minions = @catalog.class_for("Shadowmancer").fetch("resource").fetch("pools").find { |pool| pool.fetch("key") == "shadow_minions" }
    assert_equal "MIN(INT, LVL)", shadow_minions.fetch("max_formula")
    assert_same shadow_minions, @catalog.class_resource_pool_for("Shadowmancer", "shadow_minions")
    assert_equal 1, shadow_minions.fetch("summon_amount")
    assert_equal 1, shadow_minions.fetch("summon_action_cost")
    assert_equal "Heroes 2.0.1, p. 43", shadow_minions.fetch("source_ref")
    assert_equal "reaver_shadow_exploit_next_cost", @catalog.story_subclass_resource_pool_for("Shadowmancer", "Reaver", "reaver_shadow_exploit_next_cost").fetch("key")
    assert_equal 1, @catalog.story_subclass_resource_pool_for("Shadowmancer", "Reaver", "reaver_shadow_exploit_next_cost").fetch("increment_per_cast")
    assert_equal 1, @catalog.story_subclass_feature_note_for("Shadowmancer", "Reaver", "Martyr Spawn").fetch("shadow_minions_spent")
    assert_equal 1, @catalog.story_subclass_feature_note_for("Shadowmancer", "Reaver", "Reap").fetch("shadow_minions_gained")
    assert_equal 1, @catalog.story_subclass_feature_note_for("Shadowmancer", "Reaver", "My Blood, My Power").fetch("wounds_to_take")
  end

  # S-02:AC-1 S-02:AC-2 S-08:AC-4 S-09:AC-3
  test "Oathbreaker spell access and features are structured with the cited story rules" do
    assert_equal [ "True Strike", "Heal", "Warding Bond" ], @catalog.story_subclass_spell_restrictions_for("Oathsworn", "Oathbreaker")
    assert_equal "Heroes 2.0.1, p. 73", @catalog.story_subclass_spell_restriction_source_ref_for("Oathsworn", "Oathbreaker")
    assert_equal [ "Entice", "Shadow Trap", "Dread Visage" ], @catalog.story_subclass_spell_grants_for("Oathsworn", "Oathbreaker")
    assert_equal [ "Necrotic" ], @catalog.story_subclass_spell_choice_school_extensions_for("Oathsworn", "Oathbreaker")
    assert_equal [ "Paragon of Virtue" ], @catalog.story_subclass_replaced_progression_features_for("Oathsworn", "Oathbreaker")
    assert_equal [ "Pilfered Power" ], @catalog.story_subclass_replaced_progression_features_for("Shadowmancer", "Reaver")

    notes = @catalog.story_subclass_feature_notes_for("Oathsworn", "Oathbreaker")
    assert_equal [ "Dark Benediction", "Paragon of Power", "Aura of Suffering", "We All Suffer", "Bring Me Your Pain", "Torment", "Exploit", "Bloody Terror" ], notes.map { |note| note.fetch("name") }
    assert notes.all? { |note| note.fetch("source_ref") == "Heroes 2.0.1, p. 73" }
    expected_unlock_levels = { "Dark Benediction" => 1, "Paragon of Power" => 2, "Aura of Suffering" => 3, "We All Suffer" => 3, "Bring Me Your Pain" => 3, "Torment" => 7, "Exploit" => 11, "Bloody Terror" => 15 }
    assert_equal expected_unlock_levels, notes.index_with { |note| note.fetch("unlock_level") }.transform_keys { |note| note.fetch("name") }

    effects = notes.index_by { |note| note.fetch("name") }.transform_values { |note| note.fetch("effect") }
    assert_match(/True Strike.*Heal.*Warding Bond.*Entice.*Shadow Trap.*Dread Visage.*Radiant.*Necrotic/, effects.fetch("Dark Benediction"))
    assert_match(/Replaces Paragon of Virtue.*Might.*intimidate/, effects.fetch("Paragon of Power"))
    assert_match(/Reach 4.*Interpose.*Radiant Judgment/, effects.fetch("Aura of Suffering"))
    assert_match(/\+2 maximum Wounds.*gain Wounds or fail a save.*Radiant Judgment/, effects.fetch("We All Suffer"))
    assert_match(/Reaction.*willing ally.*0 HP.*exchange current HP.*Temp HP.*Wound/, effects.fetch("Bring Me Your Pain"))
    assert_match(/twice.*half.*Lay on Hands.*damage.*ignoring armor/, effects.fetch("Torment"))
    assert_match(/Reaction.*ally.*Defends.*Judgment Dice.*enemy.*Interpose.*own attack/, effects.fetch("Exploit"))
    assert_match(/disadvantage.*Wound.*three/, effects.fetch("Bloody Terror"))
  end

  # S-02:AC-1 S-02:AC-2
  test "Beastmaster companion and alternate Hunt choices are catalog-backed" do
    pool = @catalog.story_subclass_feature_choice_pools_for("Hunter", "Beastmaster", 2).sole
    assert_equal "Thrill of the Hunt", pool.fetch("name")
    assert_equal 2, pool.fetch("count")
    assert_equal [ "Go for the Throat!", "Protect Me!" ], pool.fetch("options")
    assert_equal "Heroes 2.0.1, p. 80", pool.fetch("source_ref")
    assert_match(/first 2 Thrill of the Hunt/, pool.fetch("source_quote"))
    assert_empty @catalog.story_subclass_feature_choice_pools_for("Hunter", "Shadowpath", 2)

    companion = @catalog.story_subclass_companion_rule_for("Hunter", "Beastmaster")
    assert_equal [ "Small", "Medium", "Large" ], companion.fetch("sizes")
    assert_equal({ "Small" => 1, "Medium" => 3, "Large" => 3 }, companion.fetch("minimum_level_by_size"))
    assert_equal "Heroes 2.0.1, p. 80", companion.fetch("source_ref")
    assert_match(/Choose a Small, Medium, or Large animal/, companion.fetch("source_quote"))

    abilities = @catalog.story_subclass_companion_abilities_for("Hunter", "Beastmaster")
    assert_equal({ 1 => 1, 7 => 2, 11 => 3 }, abilities.fetch("Keen Eyes").fetch("variants").fetch("Small").fetch("uses_by_level"))
    assert_equal({ 1 => 1, 7 => 2 }, abilities.fetch("Protect Me!").fetch("variants").fetch("Small").fetch("uses_by_level"))
    assert_equal "When you Defend, your companion may first attack that creature for 1d4+LVL damage.", abilities.fetch("Protect Me!").fetch("variants").fetch("Medium").fetch("source_quote")
    assert_match(/before you gain the Wound/, abilities.fetch("Protect Me!").fetch("variants").fetch("Large").fetch("effect_by_level").fetch(7))
    assert_equal({ 1 => 1, 11 => 2, 15 => 3 }, abilities.fetch("Go for the Throat!").fetch("variants").fetch("Small").fetch("uses_by_level"))
    assert_equal({ 11 => 1 }, abilities.fetch("Go for the Throat!").fetch("variants").fetch("Small").fetch("uses_per_round_by_level"))
    assert_equal "2 Thrill of the Hunt charges", abilities.fetch("Go for the Throat!").fetch("variants").fetch("Large").fetch("cost")
    assert_equal "2 actions: your companion attacks your quarry for 1d12 + (4 × your level) damage, ignoring armor; if it dies, deal half as much to another creature within Reach 4.", abilities.fetch("Go for the Throat!").fetch("variants").fetch("Large").fetch("effect")
    assert_match(/6 spaces/, abilities.fetch("Ferocious").fetch("variants").fetch("Medium").fetch("effect_by_level").fetch(15))
    assert_match(/halved/, abilities.fetch("Alpha Protector").fetch("variants").fetch("Large").fetch("effect"))
    assert_nil @catalog.story_subclass_companion_rule_for("Hunter", "Shadowpath")
  end

  # S-02:AC-1 S-02:AC-2 S-02:AC-4 S-06:AC-2
  test "published classes distinguish level-three choices from story-based subclasses" do
    expected = {
      "Berserker" => [ "Path of the Mountainheart", "Path of the Red Mist" ],
      "The Cheat" => [ "Tools of the Silent Blade", "Tools of the Scoundrel" ],
      "Commander" => [ "Champion of the Bulwark", "Champion of the Vanguard" ],
      "Hunter" => [ "Shadowpath", "Wild Heart" ],
      "Mage" => [ "Chaos", "Control" ],
      "Oathsworn" => [ "Oath of Vengeance", "Oath of Refuge" ],
      "Shadowmancer" => [ "Pact of the Red Dragon", "Pact of the Abyssal Depths" ],
      "Shepherd" => [ "Luminary of Mercy", "Luminary of Malice" ],
      "Songweaver" => [ "Herald of Snark", "Herald of Courage" ],
      "Stormshifter" => [ "Circle of Fang & Claw", "Circle of Sky & Storm" ],
      "Zephyr" => [ "Way of Flame", "Way of Pain" ]
    }
    story_based = {
      "Commander" => [ "Spellblade" ],
      "Hunter" => [ "Beastmaster" ],
      "Oathsworn" => [ "Oathbreaker" ],
      "Shadowmancer" => [ "Reaver" ]
    }

    expected.each do |class_name, subclasses|
      character_class = CharacterClass.find_by!(name: class_name)
      assert_equal subclasses, character_class.subclass_options
      assert_equal story_based.fetch(class_name, []), character_class.story_based_subclass_options
      assert_equal subclasses + story_based.fetch(class_name, []), character_class.known_subclass_options
    end

    story_based.each_key do |class_name|
      record = Rules::NimbleCatalog.story_based_subclass_records_for(class_name).first
      assert_equal "Heroes 2.0.1, p. 73", record.fetch("source_ref")
      assert_match(/GM's discretion/, record.fetch("source_quote"))
      assert_match(/replacing your existing subclass/, record.fetch("source_quote"))
    end
  end

  # S-02:AC-1 S-02:AC-4 S-06:AC-2
  test "every class subclass-choice level is read from its published progression row" do
    @catalog.classes.each_key do |class_name|
      features_by_level = @catalog.progression_for(class_name).fetch("features")
      choice_levels = features_by_level.filter_map do |level, features|
        level.to_i if Array(features).include?("Subclass choice")
      end

      assert_equal 1, choice_levels.length, "#{class_name} must publish exactly one Subclass choice feature"
      assert_equal choice_levels.first, @catalog.subclass_choice_level_for(class_name), class_name
    end
  end

  private
    def catalog_source_references(value)
      case value
      when Hash
        value.flat_map do |key, nested|
          references = if key.to_s.end_with?("source_ref") && nested.is_a?(String)
            nested.split(/\s*;\s*/)
          else
            []
          end
          references + catalog_source_references(nested)
        end
      when Array
        value.flat_map { |nested| catalog_source_references(nested) }
      else
        []
      end
    end

    def registered_source_key(reference)
      case reference
      when /\ACore Rules 2\.0\.1, / then "core_rules"
      when /\AHeroes 2\.0\.1, / then "heroes"
      when /\AGamemaster's Guide(?: 2\.0)?, / then "gamemasters_guide"
      end
    end

    def page_numbers(reference)
      page_list = reference.match(/,\s*pp?\.\s*(.+)\z/)&.captures&.first
      return [] unless page_list

      page_list.split(/,\s*/).flat_map do |page_range|
        range = page_range.match(/\A\s*(\d+)\s*[-–]\s*(\d+)\s*\z/)
        if range
          (range[1].to_i..range[2].to_i).to_a
        elsif page_range.match?(/\A\s*\d+\s*\z/)
          [ page_range.to_i ]
        else
          []
        end
      end
    end
end
