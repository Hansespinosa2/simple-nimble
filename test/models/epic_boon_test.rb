require "test_helper"

# S-02:AC-1 S-02:AC-2 S-06:AC-3 S-07:AC-2 S-09:AC-1 S-09:AC-3
class EpicBoonTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Berserker")
    @ancestry = Ancestry.find_by!(name: "Human")
    @background = Background.find_by!(name: "Fearless")
  end

  test "only the selected Epic Stats or Epic Senses boon reveals its dependent choice" do
    character = new_character("Berserker")

    assert_equal [ "Epic Boon" ], character.feature_choice_pools_for(19).map { |pool| pool.fetch("name") }

    character.feature_choices = { "Epic Boon" => { "19" => [ "Epic Stats" ] } }
    pools = character.feature_choice_pools_for(19).index_by { |pool| pool.fetch("name") }
    assert_includes pools.keys, "Epic Stats · stat increases"
    assert_not_includes pools.keys, "Epic Senses · vision"
    assert_equal 3, pools.fetch("Epic Stats · stat increases").fetch("count")

    character.feature_choices = { "Epic Boon" => { "19" => [ "Epic Senses" ] } }
    pools = character.feature_choice_pools_for(19).index_by { |pool| pool.fetch("name") }
    assert_includes pools.keys, "Epic Senses · vision"
    assert_equal [ "Blindsight 6", "Darkvision 16" ], pools.fetch("Epic Senses · vision").fetch("options")
    assert_not_includes pools.keys, "Epic Stats · stat increases"
  end

  test "Epic Stats may raise a stat above the Core Rules' typical +5 value" do
    character = new_character("Berserker")
    character.update_columns(level: 18, status: "playable", subclass_name: "Path of the Red Mist")
    character.stat_set.update!(strength: 5)
    level_up = character.level_ups.build(
      from_level: 18,
      to_level: 19,
      skill_name: "might",
      feature_choices: {
        "Epic Boon" => [ "Epic Stats" ],
        "Epic Stats · stat increases" => %w[strength dexterity will]
      }
    )
    planner = LevelUpPlanner.new(character, level_up)

    assert_equal 6, planner.preview.fetch("stats").fetch("strength")
    assert_not planner.issues.any? { |issue| issue.fetch(:message).include?("Strength is already at the +5 stat maximum") }
  end

  test "Epic Speed and Epic Foresight modify the derived values from the rules catalog" do
    baseline = new_character("Berserker")
    speed_character = character_with_boon("Berserker", "Epic Speed")
    foresight_character = character_with_boon("Berserker", "Epic Foresight")
    dexterity = { "dexterity" => 3 }

    assert_equal baseline.speed_for(level: 19) + 4, speed_character.speed_for(level: 19)
    assert_equal baseline.initiative_for(dexterity, level: 19) + 4, speed_character.initiative_for(dexterity, level: 19)
    assert_equal baseline.initiative_for(dexterity, level: 19) + 5, foresight_character.initiative_for(dexterity, level: 19)
  end

  test "Epic Defense improves each equipped shield but does nothing without one" do
    stats = { "strength" => 1, "dexterity" => 3 }
    oathsworn = new_character("Oathsworn")
    defensive_oathsworn = character_with_boon("Oathsworn", "Epic Defense")
    berserker = character_with_boon("Berserker", "Epic Defense")

    assert_equal oathsworn.armor_for(stats) + 3, defensive_oathsworn.armor_for(stats, level: 19)
    assert_equal berserker.armor_for(stats), berserker.armor_for(stats, level: 19)
  end

  test "Epic Mind adds eight mana to casters and creates a usable mana track for noncasters" do
    stats = { "strength" => 1, "dexterity" => 1, "intelligence" => 2, "will" => 1 }
    mage = character_with_boon("Mage", "Epic Mind")
    berserker = character_with_boon("Berserker", "Epic Mind")

    mage_mana = mage.derived_resource_tracks_for(stat_values: stats, level: 19).find { |track| track.fetch("key") == "mana" }
    berserker_mana = berserker.derived_resource_tracks_for(stat_values: stats, level: 19).find { |track| track.fetch("key") == "mana" }

    assert_equal 33, mage_mana.fetch("max")
    assert_equal 8, berserker_mana.fetch("max")
    assert_equal 8, berserker_mana.fetch("current")
  end

  test "Epic Mana can replace qualifying Field Rest HP healing with Mana and records the trade" do
    character = character_with_boon("Mage", "Epic Mana")
    prepare_mana_rest!(character)
    hp_before_rest = character.trait_set.current_hp
    hit_die_sides = character.hit_die_sides
    stat_bonus = character.stat_value("will")
    expected_healing = hit_die_sides + stat_bonus

    result = character.perform_field_rest!(
      mode: "catch_breath",
      hit_dice_count: 1,
      die_rolls: [ hit_die_sides.to_s ],
      convert_healing_to_mana: true
    )

    assert_equal 0, result.fetch(:hp_recovered)
    assert_equal expected_healing, result.fetch(:hp_healing_forgone)
    assert_equal expected_healing / 5, result.fetch(:mana_recovered)
    assert_equal hp_before_rest, character.reload.trait_set.current_hp
    assert_equal expected_healing / 5, character.trait_set.current_mana
    assert_equal 0, character.trait_set.current_hit_dice
    revision = character.character_revisions.where(event_type: "field_rest").sole
    assert_includes revision.summary, "forwent #{expected_healing} HP healing"
    assert_includes revision.summary, "Gamemaster's Guide 2.0, p. 23"
  end

  test "Field Rest cannot convert healing for an unselected Epic Mana boon" do
    character = character_with_boon("Mage", "Epic Speed")
    prepare_mana_rest!(character)
    original_hit_dice = character.trait_set.current_hit_dice
    original_hp = character.trait_set.current_hp

    error = assert_raises(ArgumentError) do
      character.perform_field_rest!(mode: "catch_breath", hit_dice_count: 1, die_rolls: [ "6" ], convert_healing_to_mana: true)
    end

    assert_match(/Epic Mana is required/, error.message)
    assert_equal original_hit_dice, character.reload.trait_set.current_hit_dice
    assert_equal original_hp, character.trait_set.current_hp
  end

  test "Epic Mana conversion uses HP that can actually be restored and does not spend a Hit Die when the yield is zero" do
    character = character_with_boon("Mage", "Epic Mana")
    prepare_mana_rest!(character)
    character.trait_set.update!(current_hp: character.trait_set.max_hp - 4)

    error = assert_raises(ArgumentError) do
      character.perform_field_rest!(
        mode: "catch_breath",
        hit_dice_count: 1,
        die_rolls: [ character.hit_die_sides.to_s ],
        convert_healing_to_mana: true
      )
    end

    assert_match(/cannot convert at least 5 HP/, error.message)
    assert_equal 1, character.reload.trait_set.current_hit_dice
    assert_equal 96, character.trait_set.current_hp
    assert_equal 0, character.trait_set.current_mana
    assert_empty character.character_revisions.where(event_type: "field_rest")
  end

  test "encounter-limited Epic Boons expose counters that refresh when an encounter ends" do
    agility = resource_track("Epic Agility", "epic_agility")
    knowledge = resource_track("Epic Knowledge", "epic_knowledge")
    resistance = resource_track("Epic Resistance", "epic_resistance")
    foresight_character = character_with_boon("Berserker", "Epic Foresight")
    foresight = foresight_character.derived_resource_tracks_for(
      stat_values: { "strength" => 1, "dexterity" => 1, "intelligence" => 1, "will" => 1 },
      level: 19
    ).find { |track| track.fetch("key") == "epic_foresight" }

    [ agility, knowledge, resistance, foresight ].each do |track|
      assert_equal 1, track.fetch("max")
      assert_equal 1, track.fetch("current")
    end
    assert_equal [ "encounter_end" ], agility.fetch("reset_events")
    assert_equal "Daily (reset manually)", knowledge.fetch("reset")
    assert_equal [ "encounter_end" ], resistance.fetch("reset_events")
    assert_equal [ "encounter_end" ], foresight.fetch("reset_events")

    foresight_character.update_columns(level: 19, status: "playable")
    current_tracks = foresight_character.derived_resource_tracks_for(
      stat_values: foresight_character.stat_set.attributes.slice("strength", "dexterity", "intelligence", "will"),
      level: 19
    )
    spent_tracks = current_tracks.map do |track|
      track.fetch("key") == "epic_foresight" ? track.merge("current" => 0) : track
    end
    foresight_character.trait_set.update!(resource_tracks: spent_tracks)
    foresight_character.end_encounter!

    assert_equal 1, foresight_character.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "epic_foresight" }.fetch("current")
  end

  test "Epic Stamina heals one Wound for a qualifying Catch Breath roll, not a lower roll or maximum die result" do
    source_ref = "Gamemaster's Guide 2.0, p. 23"
    low_roll = character_with_boon("Mage", "Epic Stamina")
    qualifying_roll = character_with_boon("Mage", "Epic Stamina")
    camping = character_with_boon("Mage", "Epic Stamina")
    [ low_roll, qualifying_roll, camping ].each do |character|
      character.trait_set.update!(current_hp: 1, current_wounds: 2, current_hit_dice: 1)
    end

    low_result = low_roll.perform_field_rest!(mode: "catch_breath", hit_dice_count: 1, die_rolls: [ "3" ])
    recovered_result = qualifying_roll.perform_field_rest!(mode: "catch_breath", hit_dice_count: 1, die_rolls: [ "4" ])
    camp_result = camping.perform_field_rest!(mode: "make_camp", hit_dice_count: 1)

    assert_equal 0, low_result.fetch(:wounds_recovered)
    assert_equal 2, low_roll.reload.trait_set.current_wounds
    assert_equal 1, recovered_result.fetch(:wounds_recovered)
    assert_equal 1, qualifying_roll.reload.trait_set.current_wounds
    assert_equal 0, camp_result.fetch(:wounds_recovered), "Make Camp takes the maximum die value instead of rolling"
    assert_equal 2, camping.reload.trait_set.current_wounds
    summaries = qualifying_roll.character_revisions.where(event_type: "field_rest").pluck(:summary)
    assert summaries.any? { |summary| summary.include?("healed 1 Wound") }
    assert_match(/#{Regexp.escape(source_ref)}/, Rules::NimbleCatalog.choice_pool_for("Mage", "Epic Boon").fetch("source_ref"))
  end

  private
    def prepare_mana_rest!(character)
      character.update_columns(level: 19, status: "playable")
      stats = character.stat_set.attributes.slice("strength", "dexterity", "intelligence", "will").transform_values(&:to_i)
      tracks = character.derived_resource_tracks_for(stat_values: stats, level: 19)
      mana = tracks.find { |track| track.fetch("key") == "mana" }
      tracks = tracks.map { |track| track.fetch("key") == "mana" ? track.merge("current" => 0) : track }
      character.trait_set.update!(
        current_hp: 0,
        max_hp: 100,
        current_hit_dice: 1,
        max_hit_dice: 19,
        current_mana: 0,
        max_mana: mana.fetch("max"),
        resource_tracks: tracks
      )
    end

    def new_character(class_name)
      Character.create!(
        name: "Epic Boon #{class_name} #{SecureRandom.hex(4)}",
        character_class: CharacterClass.find_by!(name: class_name),
        ancestry: @ancestry,
        background: @background,
        stat_array: "balanced"
      )
    end

    def character_with_boon(class_name, boon)
      character = new_character(class_name)
      character.update_columns(feature_choices: { "Epic Boon" => { "19" => [ boon ] } })
      character.reload
    end

    def resource_track(boon, key)
      character = character_with_boon("Berserker", boon)
      character.derived_resource_tracks_for(
        stat_values: { "strength" => 1, "dexterity" => 1, "intelligence" => 1, "will" => 1 },
        level: 19
      ).find { |track| track.fetch("key") == key }
    end
end
