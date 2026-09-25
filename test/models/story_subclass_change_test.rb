require "test_helper"

# S-02:AC-1 S-02:AC-2 S-02:AC-4 S-03:AC-3 S-03:AC-5 S-08:AC-4 S-09:AC-1
class StorySubclassChangeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Oathsworn")
    @owner = Account.create!(display_name: "Sheet owner", email: "owner-#{SecureRandom.hex(5)}@example.com")
    @gm = Account.create!(display_name: "Campaign GM", email: "gm-#{SecureRandom.hex(5)}@example.com", role: "gm")
    @player = Account.create!(display_name: "Campaign player", email: "player-#{SecureRandom.hex(5)}@example.com")
    @campaign = Campaign.create!(owner_account: @gm, name: "Oathbound Story")
    @campaign.campaign_memberships.create!(account: @gm, role: "gm")
    @campaign.campaign_memberships.create!(account: @player, role: "player")
    @character = create_oathsworn
    @share = @character.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
  end

  test "a campaign GM replaces the current subclass with a story-based subclass and records an auditable revision" do
    @character.trait_set.update!(current_hp: 7, current_wounds: 2)
    @character.spells = Spell.where(name: [ "True Strike", "Heal", "Warding Bond" ])
    ungranted_necrotic_spell = Spell.create!(name: "Unlisted Necrotic Test Spell", school: "Necrotic", tier: 1)
    original_revision_count = @character.character_revisions.count

    assert_includes @character.progression_features_through.map { |feature| feature.fetch(:name) }, "Paragon of Virtue"

    assert_difference("StorySubclassChange.count", 1) do
      assert_difference("CharacterRevision.where(event_type: 'story_subclass_change').count", 1) do
        @change = StorySubclassChangeService.call(
          character: @character,
          share: @share,
          approved_by: @gm,
          current_subclass: "Oath of Refuge",
          to_subclass: "Oathbreaker",
          story_note: "The oath fell when she chose to protect the village."
        )
      end
    end

    @character.reload
    @change.reload
    revision = @change.character_revision
    assert_equal "Oathbreaker", @character.subclass_name
    assert_not_includes @character.progression_features_through.map { |feature| feature.fetch(:name) }, "Paragon of Virtue"
    assert_equal [ "Dark Benediction", "Paragon of Power", "Aura of Suffering", "We All Suffer", "Bring Me Your Pain" ], @character.story_subclass_feature_note_entries.map { |note| note.fetch("name") }
    assert_equal 8, @character.trait_set.max_wounds
    assert_equal 2, @character.trait_set.current_wounds
    assert_equal 7, @character.trait_set.current_hp
    assert_empty @character.spells.where(name: [ "True Strike", "Heal", "Warding Bond" ])
    assert_equal [ "Dread Visage", "Entice", "Shadow Trap" ], @character.sheet_spells.where(school: "Necrotic").order(:name).pluck(:name)
    assert @character.available_spells.include?(Spell.find_by!(name: "Entice"))
    assert @character.available_spells.include?(Spell.find_by!(name: "Shadow Trap"))
    assert_not @character.available_spells.include?(Spell.find_by!(name: "Dread Visage")), "Tier 2 remains locked at Oathsworn level 3"
    assert_not ungranted_necrotic_spell.available_to?(@character), "Dark Benediction grants specific Necrotic spells, not the whole school"
    @character.update_column(:level, 4)
    assert Spell.find_by!(name: "Dread Visage").available_to?(@character)
    utility_pool = @character.spell_choice_pools_for(7).find { |pool| pool.fetch("name") == "Master of Radiance" }
    necrotic_utility = Spell.where(tier: -1, school: "Necrotic").pick(:name)
    radiant_utility = Spell.where(tier: -1, school: "Radiant").pick(:name)
    unrelated_utility = Spell.where(tier: -1).where.not(school: [ "Radiant", "Necrotic" ]).pick(:name)
    assert_includes utility_pool.fetch("options"), necrotic_utility
    assert_includes utility_pool.fetch("options"), radiant_utility
    assert_not_includes utility_pool.fetch("options"), unrelated_utility
    assert_equal "Heroes 2.0.1, p. 73", utility_pool.fetch("story_source_ref")
    granted_entries = @change&.subclass_choice_entries&.select { |entry| entry.fetch(:label) == "Granted spell" }
    assert_equal [ "Entice", "Shadow Trap", "Dread Visage" ], granted_entries&.map { |entry| entry.fetch(:value) }
    assert_equal [ "Heroes 2.0.1, p. 73" ], granted_entries.first.fetch(:source_refs)
    replaced_paragon = @change.subclass_choice_entries.find { |entry| entry.fetch(:label) == "Replaced progression feature" }
    assert_equal "Paragon of Virtue", replaced_paragon.fetch(:value)
    assert_equal [ "Heroes 2.0.1, p. 73" ], replaced_paragon.fetch(:source_refs)
    assert_equal "Oath of Refuge", @change.from_subclass
    assert_equal "Oathbreaker", @change.to_subclass
    assert_equal @campaign, @change.campaign
    assert_equal @gm, @change.approved_by_account
    assert_equal "Heroes 2.0.1, p. 73", @change.source_ref
    assert_equal "The oath fell when she chose to protect the village.", @change.story_note
    assert_equal "story_subclass_change", revision.event_type
    assert_equal "Oathbreaker", revision.snapshot.dig("character", "subclass_name")
    assert_includes revision.summary, "Oath of Refuge → Oathbreaker"
    assert_includes revision.summary, @change.story_note
    assert_equal original_revision_count + 1, @character.character_revisions.count
  end

  test "a campaign player cannot call the approval service" do
    assert_no_difference("StorySubclassChange.count") do
      error = assert_raises(ArgumentError) do
        StorySubclassChangeService.call(
          character: @character,
          share: @share,
          approved_by: @player,
          current_subclass: "Oath of Refuge",
          to_subclass: "Oathbreaker",
          story_note: "The story calls for it."
        )
      end
      assert_match(/only this campaign's GM/i, error.message)
    end
    assert_equal "Oath of Refuge", @character.reload.subclass_name
  end

  test "a story subclass change preserves legacy languages that have not been explicitly reselected" do
    commander = Character.create!(
      name: "Legacy Language Hero",
      account: @owner,
      character_class: CharacterClass.find_by!(name: "Commander"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Draconic", "Primordial" ],
      skill_set_attributes: { might: 7 }
    )
    commander.finalize_creation!
    commander.update_columns(
      level: 3,
      status: "playable",
      subclass_name: "Champion of the Bulwark",
      language_choices: [],
      languages: "Common, Dwarvish, Draconic, Primordial"
    )
    commander.skill_set.update!(might: 9)
    spell_choices = {
      "Deep Knowledge · tiered spell" => { "3" => "Flame Dart" },
      "Deep Knowledge · Utility Spell" => { "3" => "Firebrand" }
    }
    share = commander.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")

    StorySubclassChangeService.call(
      character: commander,
      share:,
      approved_by: @gm,
      current_subclass: "Champion of the Bulwark",
      to_subclass: "Spellblade",
      story_note: "An alliance with the fire cult changed the commander's path.",
      spell_choices:
    )

    commander.reload
    assert_equal "Spellblade", commander.subclass_name
    assert_equal [], commander.language_choices
    assert_equal "Common, Dwarvish, Draconic, Primordial", commander.languages
    assert_includes commander.creation_issues.map { |issue| issue.fetch(:message) }, "Choose 2 more languages for your INT."
  end

  test "Spellblade approval requires and audits every Deep Knowledge choice already earned" do
    commander = create_commander
    share = commander.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
    pools = commander.story_subclass_spell_choice_pools_through(subclass_name: "Spellblade")
    tiered_pool = pools.find { |pool| pool.fetch("kind") == "spell_up_to_tier" }
    utility_pool = pools.find { |pool| pool.fetch("kind") == "utility_spell_any" }

    missing_choices = assert_raises(ArgumentError) do
      StorySubclassChangeService.call(
        character: commander,
        share:,
        approved_by: @gm,
        current_subclass: "Champion of the Bulwark",
        to_subclass: "Spellblade",
        story_note: "The arcane pact reshapes the commander's path."
      )
    end
    assert_match(/Deep Knowledge/, missing_choices.message)
    assert_equal "Champion of the Bulwark", commander.reload.subclass_name
    assert_empty commander.story_subclass_changes

    tiered_spell = Spell.find_by!(name: "Flame Dart")
    utility_spell = Spell.find_by!(name: "Firebrand")
    spell_choices = {
      tiered_pool.fetch("name") => { tiered_pool.fetch("level").to_s => tiered_spell.name },
      utility_pool.fetch("name") => { utility_pool.fetch("level").to_s => utility_spell.name }
    }
    change = StorySubclassChangeService.call(
      character: commander,
      share:,
      approved_by: @gm,
      current_subclass: "Champion of the Bulwark",
      to_subclass: "Spellblade",
      story_note: "The arcane pact reshapes the commander's path.",
      spell_choices:
    )

    assert_equal "Spellblade", commander.reload.subclass_name
    assert_equal spell_choices.transform_values { |by_level| by_level.transform_values { |spell| [ spell ] } }, change.subclass_choices.fetch("spell_choices")
    assert_includes change.subclass_choice_entries.map { |entry| entry.fetch(:source_refs) }.flatten, "Heroes 2.0.1, p. 76"
    assert_includes commander.recorded_spell_choices.fetch(tiered_pool.fetch("name")), tiered_spell.name
    assert_includes commander.recorded_spell_choices.fetch(utility_pool.fetch("name")), utility_spell.name
    assert tiered_spell.available_to?(commander)
    assert_includes commander.sheet_spells.pluck(:name), tiered_spell.name
    assert_includes change.character_revision.snapshot.dig("progression", "spell_choices").map { |entry| entry.fetch("selected") }.flatten, tiered_spell.name

    commander.update_columns(level: 6)
    next_level = commander.level_ups.build(from_level: 6, to_level: 7)
    next_level_pools = LevelUpPlanner.new(commander, next_level).spell_choice_pools
    next_tiered_pool = next_level_pools.find { |pool| pool.fetch("name") == tiered_pool.fetch("name") }
    next_utility_pool = next_level_pools.find { |pool| pool.fetch("name") == utility_pool.fetch("name") }
    assert_equal 2, next_tiered_pool.fetch("max_tier")
    assert_equal 7, next_tiered_pool.fetch("level")
    assert_includes next_tiered_pool.fetch("options"), Spell.where(tier: 2).first!.name
    assert_equal "Choose any tier 2 (or lower) spell and any Utility Spell.", next_tiered_pool.fetch("source_quote")
    assert_equal 7, next_utility_pool.fetch("level")
  end

  test "Spellblade story approval rejects an Order already known from the class" do
    commander = create_commander
    commander.update_columns(
      level: 4,
      feature_choices: { "Commander's Orders" => { "2" => [ "Face Me!", "Hold the Line!" ] } }
    )
    share = commander.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
    spell_choices = {
      "Deep Knowledge · tiered spell" => { "3" => "Flame Dart" },
      "Deep Knowledge · Utility Spell" => { "3" => "Firebrand" }
    }

    error = assert_raises(ArgumentError) do
      StorySubclassChangeService.call(
        character: commander,
        share:,
        approved_by: @gm,
        current_subclass: "Champion of the Bulwark",
        to_subclass: "Spellblade",
        story_note: "An alliance with the fire cult changes the commander's path.",
        spell_choices:,
        feature_choices: { "Arcane Command" => { "4" => "Order: Face Me!" } }
      )
    end

    assert_equal "Choose a different Commander’s Order; Face Me! is already known.", error.message
    assert_equal "Champion of the Bulwark", commander.reload.subclass_name
    assert_empty commander.story_subclass_changes
  end

  test "Spellblade story approval rejects a spell duplicated across granted choice pools" do
    commander = create_commander
    commander.update_columns(level: 4)
    share = commander.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
    repeated_spell = "Flame Dart"
    spell_choices = {
      "Deep Knowledge · tiered spell" => { "3" => repeated_spell },
      "Deep Knowledge · Utility Spell" => { "3" => "Firebrand" }
    }

    error = assert_raises(ArgumentError) do
      StorySubclassChangeService.call(
        character: commander,
        share:,
        approved_by: @gm,
        current_subclass: "Champion of the Bulwark",
        to_subclass: "Spellblade",
        story_note: "An alliance with the fire cult changes the commander's path.",
        spell_choices:,
        feature_choices: { "Arcane Command" => { "4" => "Spell: #{repeated_spell}" } }
      )
    end

    assert_match(/Choose a different spell/, error.message)
    assert_includes error.message, repeated_spell
    assert_equal "Champion of the Bulwark", commander.reload.subclass_name
    assert_empty commander.story_subclass_changes
  end

  test "Spellblade approval rejects spells above the Deep Knowledge tier" do
    commander = create_commander
    share = commander.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
    pools = commander.story_subclass_spell_choice_pools_through(subclass_name: "Spellblade")
    tiered_pool = pools.find { |pool| pool.fetch("kind") == "spell_up_to_tier" }
    utility_pool = pools.find { |pool| pool.fetch("kind") == "utility_spell_any" }
    over_tier_spell = Spell.where(tier: 2).first!
    spell_choices = {
      tiered_pool.fetch("name") => { tiered_pool.fetch("level").to_s => over_tier_spell.name },
      utility_pool.fetch("name") => { utility_pool.fetch("level").to_s => Spell.find_by!(name: "Firebrand").name }
    }

    error = assert_raises(ArgumentError) do
      StorySubclassChangeService.call(
        character: commander,
        share:,
        approved_by: @gm,
        current_subclass: "Champion of the Bulwark",
        to_subclass: "Spellblade",
        story_note: "A spell beyond the granted tier is not legal.",
        spell_choices:
      )
    end

    assert_match(/not a legal Deep Knowledge/, error.message)
    assert_equal "Champion of the Bulwark", commander.reload.subclass_name
    assert_empty commander.story_subclass_changes
  end

  # S-02:AC-1 S-02:AC-2 S-08:AC-4 S-09:AC-3
  test "Spellblade reconciles earned Commander choices and turns arcane picks into known spells" do
    commander = create_commander
    commander.update_columns(
      level: 10,
      feature_choices: {
        "Commander's Orders" => { "2" => [ "Face Me!", "Hold the Line!" ] },
        "Combat Tactics" => { "4" => [ "Heavy Strike" ] },
        "Weapon Mastery" => { "6" => [ "Slashing" ], "10" => [ "Piercing" ] },
        "Combat Ability" => { "6" => [ "Lunging Strike" ], "8" => [ "+1 max Combat Dice" ], "10" => [ "Sweeping Strike" ] }
      }
    )
    allocated_skills = Character::SKILL_NAMES.index_with { |skill| commander.skill_value(skill) }
    7.times do
      skill = Character::SKILL_NAMES.find { |candidate| allocated_skills.fetch(candidate) < 12 }
      allocated_skills[skill] += 1
    end
    commander.skill_set.update!(allocated_skills)
    share = commander.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
    tier_one_spell = Spell.where(tier: 1).first!
    tier_two_spell = Spell.where(tier: 2).where.not(name: tier_one_spell.name).first!
    arcane_spells = Spell.where(tier: 0..1).where.not(name: [ tier_one_spell.name, tier_two_spell.name ]).select do |spell|
      spell.class_restriction.blank? || Array(spell.class_restriction).include?("Commander")
    end
    arcane_spell_one, arcane_spell_two = arcane_spells.first(2)
    utility_spells = Spell.where(tier: -1).order(:name).first(2)
    spell_choices = {
      "Deep Knowledge · tiered spell" => { "3" => tier_one_spell.name, "7" => tier_two_spell.name },
      "Deep Knowledge · Utility Spell" => { "3" => utility_spells.first.name, "7" => utility_spells.last.name }
    }
    feature_choices = {
      "Arcane Command" => {
        "4" => [ "Order: I Can Do This ALL DAY!" ],
        "6" => [ "Spell: #{arcane_spell_one.name}" ],
        "10" => [ "Order: Reposition!" ]
      },
      "Combat Ability" => {
        "6" => [ "Spell: #{arcane_spell_two.name}" ],
        "8" => [ "+1 max Combat Dice" ],
        "10" => [ "Order: Move it! Move it!" ]
      }
    }

    eligible_pools = commander.story_subclass_feature_choice_pools_through(subclass_name: "Spellblade")
    assert_equal 6, eligible_pools.length
    assert_includes eligible_pools.find { |pool| pool.fetch("name") == "Combat Ability" && pool.fetch("level") == 6 }.fetch("options"), "Spell: #{arcane_spell_one.name}"
    assert_not_includes eligible_pools.find { |pool| pool.fetch("name") == "Combat Ability" && pool.fetch("level") == 6 }.fetch("options"), "Heavy Strike"

    change = StorySubclassChangeService.call(
      character: commander,
      share:,
      approved_by: @gm,
      current_subclass: "Champion of the Bulwark",
      to_subclass: "Spellblade",
      story_note: "A bargain with the archmage reshapes the commander's art.",
      spell_choices:,
      feature_choices:
    )

    commander.reload
    assert_equal "Spellblade", commander.subclass_name
    assert_equal [ "Order: I Can Do This ALL DAY!", "Spell: #{arcane_spell_one.name}", "Order: Reposition!" ], commander.recorded_feature_choices.fetch("Arcane Command")
    assert_equal [ "Spell: #{arcane_spell_two.name}", "+1 max Combat Dice", "Order: Move it! Move it!" ], commander.recorded_feature_choices.fetch("Combat Ability")
    assert_not commander.recorded_feature_choices.key?("Combat Tactics")
    assert_not commander.recorded_feature_choices.key?("Weapon Mastery")
    assert_includes commander.story_granted_spell_names, arcane_spell_one.name
    assert_includes commander.story_granted_spell_names, arcane_spell_two.name
    assert_includes commander.sheet_spells.pluck(:name), arcane_spell_one.name
    assert arcane_spell_one.available_to?(commander)
    empowered_orders = commander.story_subclass_empowered_order_entries.index_by { |entry| entry.fetch(:name) }
    assert_equal 5, empowered_orders.length
    assert_equal "Glimmering Decree", empowered_orders.fetch("Face Me!").fetch(:arcane_name)
    assert_includes empowered_orders.fetch("Reposition!").fetch(:effect), "exchange places"
    assert_equal "Firebrand", commander.story_subclass_initiative_feature_entries.sole.fetch("name")
    assert_equal [ "Heroes 2.0.1, p. 22", "Heroes 2.0.1, pp. 20, 22" ], change.subclass_choices.fetch("source_refs").fetch("replaced_feature_choices").values.uniq.sort
    assert_equal [ "Combat Ability", "Combat Tactics", "Weapon Mastery" ], change.subclass_choices.fetch("replaced_feature_choices").keys.sort
    assert change.subclass_choice_entries.any? { |entry| entry.fetch(:label) == "Replaced · Level 4 · Combat Tactics" && entry.fetch(:value) == "Heavy Strike" }
    assert_not_includes commander.progression_features_for(14), "Weapon Mastery (3)"
    assert_includes commander.subclass_progression_features_through.map { |feature| feature.fetch(:name) }, "Arcane Command"
  end

  # S-02:AC-1 S-02:AC-2 S-08:AC-4 S-09:AC-3
  test "Reaver approval removes patron powers and records a scaling one-hit Bonescythe" do
    shadowmancer = create_shadowmancer
    share = shadowmancer.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
    shadow_blast = Spell.find_by!(name: "Shadow Blast")
    tiered_shadow_spell = Spell.where(school: "Necrotic", tier: 1).where.not(name: "Shadow Blast").first!
    shadowmancer.spells << shadow_blast
    shadowmancer.spells << tiered_shadow_spell
    old_tracks = shadowmancer.trait_set.resource_tracks.map do |track|
      track.fetch("key") == "pilfered_power" ? track.merge("current" => 1) : track
    end
    shadowmancer.trait_set.update!(resource_tracks: old_tracks)
    assert shadow_blast.available_to?(shadowmancer)

    change = StorySubclassChangeService.call(
      character: shadowmancer,
      share:,
      approved_by: @gm,
      current_subclass: "Pact of the Red Dragon",
      to_subclass: "Reaver",
      story_note: "The patron abandons the Shadowmancer, leaving a weapon made of bone."
    )

    shadowmancer.reload
    assert_not shadow_blast.available_to?(shadowmancer)
    assert_not_includes shadowmancer.available_spells, shadow_blast
    assert_not_includes shadowmancer.sheet_spells, shadow_blast
    assert_not shadowmancer.spells.exists?(id: shadow_blast.id)
    assert_includes shadowmancer.available_spells, tiered_shadow_spell
    tracks = shadowmancer.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_not tracks.key?("pilfered_power")
    assert_equal 2, tracks.fetch("shadow_minions").fetch("max")
    assert_equal 1, tracks.fetch("reaver_shadow_exploit_next_cost").fetch("current")
    assert_equal "Shadow Minions", shadowmancer.trait_set.resource_name
    replaced_resource = change.subclass_choice_entries.find { |entry| entry.fetch(:label) == "Replaced resource · Pilfered Power" }
    assert_equal "1 / 2", replaced_resource.fetch(:value)
    assert_equal [ "Heroes 2.0.1, p. 44" ], replaced_resource.fetch(:source_refs)
    assert_equal "Heroes 2.0.1, p. 44", change.subclass_choices.dig("source_refs", "replaced_resource_pools", "pilfered_power")
    replaced_spell = change.subclass_choice_entries.find { |entry| entry.fetch(:label) == "No longer castable" }
    assert_equal "Shadow Blast", replaced_spell.fetch(:value)
    assert_equal [ "Heroes 2.0.1, p. 78" ], replaced_spell.fetch(:source_refs)
    assert_equal [ "Shadow Blast" ], change.subclass_choices.fetch("replaced_spells")

    features = shadowmancer.subclass_progression_features_through.map { |feature| feature.fetch(:name) }
    assert_includes features, "Hollow One"
    assert_includes features, "Bonescythe"
    assert_not_includes shadowmancer.progression_features_through.map { |feature| feature.fetch(:name) }, "Pilfered Power"
    assert_includes shadowmancer.story_subclass_feature_note_entries.map { |note| note.fetch("name") }, "Shadow Exploit"
    weapon = shadowmancer.story_subclass_weapon_entry
    assert_equal "2d12", weapon.fetch(:damage_dice)
    assert_equal 1, weapon.fetch(:additional_dice_per_interval)
    assert_equal 5, weapon.fetch(:damage_dice_interval)
    assert_includes weapon.fetch(:damage_effect), "DEX (2) necrotic damage per die"
    assert_equal 2, weapon.fetch(:reach)

    unknown_tiered_spell = Spell.create!(name: "Unlearned Necrotic Test Spell", school: "Necrotic", tier: 1)
    assert unknown_tiered_spell.available_to?(shadowmancer)
    assert_not shadowmancer.sheet_spells.exists?(id: unknown_tiered_spell.id)
    assert_raises(ArgumentError) { shadowmancer.use_shadow_exploit!(spell_name: unknown_tiered_spell.name) }

    shadowmancer.summon_bonescythe!
    assert shadowmancer.reload.bonescythe_summoned?
    assert_equal 2, shadowmancer.trait_set.current_actions
    shadowmancer.mark_bonescythe_hit!
    assert_not shadowmancer.reload.bonescythe_summoned?
    assert shadowmancer.character_revisions.exists?(event_type: "weapon_shattered")

    shadowmancer.summon_shadow_minion!
    assert_equal 1, shadowmancer.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
    assert_equal 1, shadowmancer.trait_set.current_actions
    shadowmancer.use_shadow_exploit!(spell_name: tiered_shadow_spell.name)
    assert_equal 0, shadowmancer.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
    assert_equal 2, shadowmancer.trait_set.resource_tracks.find { |track| track.fetch("key") == "reaver_shadow_exploit_next_cost" }.fetch("current")

    tracks_with_two_minions = shadowmancer.trait_set.resource_tracks.map do |track|
      track.fetch("key") == "shadow_minions" ? track.merge("current" => 2) : track
    end
    shadowmancer.trait_set.update!(resource_tracks: tracks_with_two_minions)
    shadowmancer.use_shadow_exploit!(spell_name: tiered_shadow_spell.name)
    assert_equal 0, shadowmancer.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
    assert_equal 3, shadowmancer.trait_set.resource_tracks.find { |track| track.fetch("key") == "reaver_shadow_exploit_next_cost" }.fetch("current")
    assert_raises(ArgumentError) { shadowmancer.use_shadow_exploit!(spell_name: tiered_shadow_spell.name) }

    { 3 => "2d12", 4 => "2d12", 5 => "3d12", 10 => "4d12", 20 => "6d12" }.each do |level, expected_dice|
      shadowmancer.update_column(:level, level)
      assert_equal expected_dice, shadowmancer.story_subclass_weapon_entry.fetch(:damage_dice)
    end

    shadowmancer.update_column(:level, 11)
    assert_raises(ArgumentError) { shadowmancer.use_my_blood_my_power!(spell_name: unknown_tiered_spell.name) }
    blood_revision = shadowmancer.use_my_blood_my_power!(spell_name: tiered_shadow_spell.name)
    assert_equal 1, shadowmancer.trait_set.reload.current_wounds
    assert_includes blood_revision.summary, "Tier #{shadowmancer.character_class.spell_tier_for(11)}"
    assert shadowmancer.character_revisions.exists?(event_type: "my_blood_my_power")
    shadowmancer.trait_set.update!(current_wounds: shadowmancer.trait_set.max_wounds)
    assert_raises(ArgumentError) { shadowmancer.use_my_blood_my_power!(spell_name: tiered_shadow_spell.name) }

    shadowmancer.update_column(:level, 7)
    assert_raises(ArgumentError) { shadowmancer.mark_bonescythe_hit!(outcome: "critical") }
    shadowmancer.summon_bonescythe!
    reap_revision = shadowmancer.mark_bonescythe_hit!(outcome: "critical")
    assert_equal 1, shadowmancer.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
    assert_includes reap_revision.summary, "Reap summoned a Shadow Minion"
    shadowmancer.martyr_spawn!
    assert_equal 0, shadowmancer.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
    shadowmancer.end_encounter!
    assert_equal 0, shadowmancer.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
    assert_equal 1, shadowmancer.trait_set.resource_tracks.find { |track| track.fetch("key") == "reaver_shadow_exploit_next_cost" }.fetch("current")
    assert_not shadowmancer.bonescythe_summoned?
  end

  # S-02:AC-1 S-02:AC-2 S-07:AC-2 S-09:AC-3
  test "Reaver combat costs and minion gains follow the source catalog" do
    reaver = create_shadowmancer
    share = reaver.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
    tiered_spell = Spell.where(school: "Necrotic", tier: 1).where.not(name: "Shadow Blast").first!
    reaver.spells << tiered_spell
    StorySubclassChangeService.call(
      character: reaver,
      share:,
      approved_by: @gm,
      current_subclass: "Pact of the Red Dragon",
      to_subclass: "Reaver",
      story_note: "The patron leaves a weapon of bone."
    )
    reaver.reload

    summon_rule = Rules::NimbleCatalog.class_resource_pool_for("Shadowmancer", "shadow_minions")
    exploit_rule = Rules::NimbleCatalog.story_subclass_resource_pool_for("Shadowmancer", "Reaver", "reaver_shadow_exploit_next_cost")
    martyr_rule = Rules::NimbleCatalog.story_subclass_feature_note_for("Shadowmancer", "Reaver", "Martyr Spawn")
    reap_rule = Rules::NimbleCatalog.story_subclass_feature_note_for("Shadowmancer", "Reaver", "Reap")
    my_blood_rule = Rules::NimbleCatalog.story_subclass_feature_note_for("Shadowmancer", "Reaver", "My Blood, My Power")
    weapon_rules = Rules::NimbleCatalog.data.dig("story_subclass_weapon_rules", "Shadowmancer", "Reaver")
    original_rules = {
      summon: summon_rule.dup,
      exploit: exploit_rule.dup,
      martyr: martyr_rule.dup,
      reap: reap_rule.dup,
      my_blood: my_blood_rule.dup,
      bonescythe: weapon_rules.fetch("Bonescythe")
    }

    set_minions = lambda do |current|
      tracks = reaver.trait_set.resource_tracks.map do |track|
        track.fetch("key") == "shadow_minions" ? track.merge("current" => current) : track
      end
      reaver.trait_set.update!(resource_tracks: tracks)
    end

    begin
      summon_rule["summon_amount"] = 2
      summon_rule["summon_action_cost"] = 2
      reaver.trait_set.update!(current_actions: 1)
      assert_match(/need 2 actions/i, assert_raises(ArgumentError) { reaver.summon_shadow_minion! }.message)
      reaver.trait_set.update!(current_actions: 3)
      summon_revision = reaver.summon_shadow_minion!
      assert_equal 2, reaver.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
      assert_equal 1, reaver.trait_set.current_actions
      assert_includes summon_revision.summary, "2 Shadow Minions (2 actions)"

      weapon_rules["Bonescythe"] = original_rules.fetch(:bonescythe).merge("action_cost" => 2)
      reaver.trait_set.update!(current_actions: 1)
      assert_match(/need at least 2 actions/i, assert_raises(ArgumentError) { reaver.summon_bonescythe! }.message)
      reaver.trait_set.update!(current_actions: 2)
      weapon_revision = reaver.summon_bonescythe!
      assert_equal 0, reaver.trait_set.current_actions
      assert_includes weapon_revision.summary, "(2 actions)"

      set_minions.call(1)
      exploit_rule["increment_per_cast"] = 3
      reaver.use_shadow_exploit!(spell_name: tiered_spell.name)
      exploit_track = reaver.trait_set.resource_tracks.find { |track| track.fetch("key") == "reaver_shadow_exploit_next_cost" }
      assert_equal 4, exploit_track.fetch("current"), "the next cost must increase by the catalog increment, not a duplicated constant"

      martyr_rule["shadow_minions_spent"] = 2
      set_minions.call(1)
      assert_match(/do not have a Shadow Minion to sacrifice/i, assert_raises(ArgumentError) { reaver.martyr_spawn! }.message)
      set_minions.call(2)
      martyr_revision = reaver.martyr_spawn!
      assert_equal 0, reaver.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
      assert_includes martyr_revision.summary, "sacrificed 2 Shadow Minions"

      reaver.update_column(:level, 7)
      reap_rule["shadow_minions_gained"] = 2
      set_minions.call(0)
      reap_revision = reaver.mark_bonescythe_hit!(outcome: "critical")
      assert_equal 2, reaver.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
      assert_includes reap_revision.summary, "Reap summoned 2 Shadow Minions"

      reaver.update_column(:level, 11)
      my_blood_rule["wounds_to_take"] = 2
      reaver.trait_set.update!(current_wounds: reaver.trait_set.max_wounds - 1)
      assert_match(/requires room to take 2 Wounds/i, assert_raises(ArgumentError) { reaver.use_my_blood_my_power!(spell_name: tiered_spell.name) }.message)
      reaver.trait_set.update!(current_wounds: 0)
      blood_revision = reaver.use_my_blood_my_power!(spell_name: tiered_spell.name)
      assert_equal 2, reaver.trait_set.reload.current_wounds
      assert_includes blood_revision.summary, "Took 2 Wounds"
    ensure
      summon_rule.replace(original_rules.fetch(:summon))
      exploit_rule.replace(original_rules.fetch(:exploit))
      martyr_rule.replace(original_rules.fetch(:martyr))
      reap_rule.replace(original_rules.fetch(:reap))
      my_blood_rule.replace(original_rules.fetch(:my_blood))
      weapon_rules["Bonescythe"] = original_rules.fetch(:bonescythe)
    end
  end

  test "Beastmaster approval records the companion and reselects the first two Hunt abilities" do
    hunter = create_hunter
    hunter.update_columns(feature_choices: { "Thrill of the Hunt" => [ "Fleet Feet", "Wild Instinct" ] })
    hunter.update_columns(
      stat_array: "balanced",
      stat_assignments: { "strength" => 0, "dexterity" => 2, "intelligence" => 1, "will" => 1 },
      language_choices: [],
      languages: "Common, Dwarvish"
    )
    hunter.stat_set.update!(strength: 0, dexterity: 2, intelligence: 1, will: 1)
    skill_values = Character::SKILL_NAMES.index_with { |skill| hunter.skill_initial_value(skill) }
    skill_values["finesse"] += 6
    hunter.skill_set.update!(skill_values)
    share = hunter.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
    feature_pool = hunter.story_subclass_feature_choice_pools_through(subclass_name: "Beastmaster").sole
    assert_equal [ "Go for the Throat!", "Protect Me!" ], feature_pool.fetch("story_options")
    assert_equal 2, feature_pool.fetch("count")
    feature_choices = { "Thrill of the Hunt" => { "2" => [ "Go for the Throat!", "Protect Me!" ] } }

    incomplete_choices = assert_raises(ArgumentError) do
      StorySubclassChangeService.call(
        character: hunter,
        share:,
        approved_by: @gm,
        current_subclass: "Shadowpath",
        to_subclass: "Beastmaster",
        story_note: "The story grants a companion.",
        feature_choices: { "Thrill of the Hunt" => { "2" => [ "Go for the Throat!" ] } },
        companion_name: "Ember",
        companion_size: "Small"
      )
    end
    assert_match(/choose 2 options/i, incomplete_choices.message)

    illegal_choice = assert_raises(ArgumentError) do
      StorySubclassChangeService.call(
        character: hunter,
        share:,
        approved_by: @gm,
        current_subclass: "Shadowpath",
        to_subclass: "Beastmaster",
        story_note: "The story grants a companion.",
        feature_choices: { "Thrill of the Hunt" => { "2" => [ "Fleet Feet", "Fake Ability" ] } },
        companion_name: "Ember",
        companion_size: "Small"
      )
    end
    assert_match(/Fake Ability is not a legal Thrill of the Hunt choice/, illegal_choice.message)

    bad_size = assert_raises(ArgumentError) do
      StorySubclassChangeService.call(
        character: hunter,
        share:,
        approved_by: @gm,
        current_subclass: "Shadowpath",
        to_subclass: "Beastmaster",
        story_note: "The rescued hawk chooses to stay.",
        feature_choices:,
        companion_name: "Ember",
        companion_size: "Tiny"
      )
    end
    assert_match(/companion size/i, bad_size.message)
    assert_equal "Shadowpath", hunter.reload.subclass_name
    assert_empty hunter.story_subclass_changes

    change = StorySubclassChangeService.call(
      character: hunter,
      share:,
      approved_by: @gm,
      current_subclass: "Shadowpath",
      to_subclass: "Beastmaster",
      story_note: "The rescued hawk chooses to stay.",
      feature_choices:,
      companion_name: "Ember",
      companion_size: "Small"
    )

    hunter.reload
    assert_equal "Beastmaster", hunter.subclass_name
    assert_equal [], hunter.language_choices
    assert_equal "Common, Dwarvish", hunter.languages
    assert_equal [ "Go for the Throat!", "Protect Me!" ], hunter.recorded_feature_choices.fetch("Thrill of the Hunt")
    assert_equal({ "size" => "Small", "name" => "Ember" }, hunter.subclass_choices.fetch("companion"))
    assert_equal({ "size" => "Small", "name" => "Ember" }, change.subclass_choices.fetch("companion"))
    assert_equal [ "Heroes 2.0.1, p. 28", "Heroes 2.0.1, p. 80" ], hunter.feature_choice_entries_through.first.fetch(:source_refs)
    companion_entry = change.subclass_choice_entries.find { |entry| entry.fetch(:label) == "Companion" }
    assert_equal "Small Ember", companion_entry.fetch(:value)
    assert_equal hunter.subclass_choices, change.character_revision.snapshot.dig("character", "subclass_choices")

    tracks = hunter.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal [ "thrill_of_the_hunt", "beastmaster_keen_eyes", "beastmaster_protect_me", "beastmaster_go_for_the_throat" ], tracks.keys
    assert_equal [ 1, 1, 1 ], %w[beastmaster_keen_eyes beastmaster_protect_me beastmaster_go_for_the_throat].map { |key| tracks.fetch(key).fetch("max") }
    assert tracks.fetch("beastmaster_go_for_the_throat").fetch("source_quote").include?("1d4+LVL")

    ability_entries = hunter.story_subclass_companion_ability_entries.index_by { |entry| entry.fetch(:name) }
    assert_equal "Mark a target for free.", ability_entries.fetch("Keen Eyes").fetch(:effect)
    assert_equal "1 / 1 per encounter", ability_entries.fetch("Keen Eyes").fetch(:uses)
    assert_equal "1 Thrill of the Hunt charge", ability_entries.fetch("Go for the Throat!").fetch(:cost)
    assert_equal "Heroes 2.0.1, p. 80", ability_entries.fetch("Protect Me!").fetch(:source_ref)
    level_eleven_tracks = hunter.derived_resource_tracks_for(stat_values: {}, level: 11).index_by { |track| track.fetch("key") }
    assert_equal 3, level_eleven_tracks.fetch("beastmaster_keen_eyes").fetch("max")
    assert_equal 2, level_eleven_tracks.fetch("beastmaster_protect_me").fetch("max")
    assert_equal 2, level_eleven_tracks.fetch("beastmaster_go_for_the_throat").fetch("max")
    level_fifteen_tracks = hunter.derived_resource_tracks_for(stat_values: {}, level: 15).index_by { |track| track.fetch("key") }
    assert_equal 3, level_fifteen_tracks.fetch("beastmaster_go_for_the_throat").fetch("max")

    spent_tracks = hunter.trait_set.resource_tracks.map { |track| track.merge("current" => 0) }
    hunter.trait_set.update!(resource_tracks: spent_tracks)
    hunter.end_encounter!
    refreshed_tracks = hunter.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal [ 1, 1, 1 ], %w[beastmaster_keen_eyes beastmaster_protect_me beastmaster_go_for_the_throat].map { |key| refreshed_tracks.fetch(key).fetch("current") }
    assert_equal 0, refreshed_tracks.fetch("thrill_of_the_hunt").fetch("current")
    assert hunter.character_revisions.exists?(event_type: "encounter_end")

    medium_hunter = create_hunter
    medium_share = medium_hunter.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
    StorySubclassChangeService.call(
      character: medium_hunter,
      share: medium_share,
      approved_by: @gm,
      current_subclass: "Shadowpath",
      to_subclass: "Beastmaster",
      story_note: "A wolf joins the hunt.",
      feature_choices:,
      companion_name: "Fang",
      companion_size: "Medium"
    )
    medium_hunter.reload
    medium_abilities = medium_hunter.story_subclass_companion_ability_entries.index_by { |entry| entry.fetch(:name) }
    assert_includes medium_abilities.fetch("Ferocious").fetch(:effect), "2 spaces"
    assert_includes medium_abilities.fetch("Protect Me!").fetch(:effect), "1d4 + your level"
    assert_equal "1 action", medium_abilities.fetch("Go for the Throat!").fetch(:action_cost)
    assert_equal "1 Thrill of the Hunt charge", medium_abilities.fetch("Go for the Throat!").fetch(:cost)
    assert_equal [ "thrill_of_the_hunt", "beastmaster_go_for_the_throat" ], medium_hunter.trait_set.resource_tracks.map { |track| track.fetch("key") }
    assert_includes medium_hunter.story_subclass_companion_ability_entries(level: 15).find { |entry| entry.fetch(:name) == "Ferocious" }.fetch(:effect), "6 spaces"

    large_hunter = create_hunter
    large_share = large_hunter.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
    StorySubclassChangeService.call(
      character: large_hunter,
      share: large_share,
      approved_by: @gm,
      current_subclass: "Shadowpath",
      to_subclass: "Beastmaster",
      story_note: "A drake accepts the oath.",
      feature_choices:,
      companion_name: "Cinder",
      companion_size: "Large"
    )
    large_hunter.reload
    large_abilities = large_hunter.story_subclass_companion_ability_entries.index_by { |entry| entry.fetch(:name) }
    assert_includes large_abilities.fetch("Alpha Protector").fetch(:effect), "halved"
    assert_equal "2 actions", large_abilities.fetch("Go for the Throat!").fetch(:action_cost)
    assert_equal "2 Thrill of the Hunt charges", large_abilities.fetch("Go for the Throat!").fetch(:cost)
    assert_includes large_abilities.fetch("Protect Me!").fetch(:effect), "After you gain a Wound"
    assert_equal [ "thrill_of_the_hunt", "beastmaster_protect_me", "beastmaster_go_for_the_throat" ], large_hunter.trait_set.resource_tracks.map { |track| track.fetch("key") }

    below_minimum = create_hunter
    below_minimum.update_columns(level: 2)
    below_minimum_share = below_minimum.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")
    error = assert_raises(ArgumentError) do
      StorySubclassChangeService.call(
        character: below_minimum,
        share: below_minimum_share,
        approved_by: @gm,
        current_subclass: "Shadowpath",
        to_subclass: "Beastmaster",
        story_note: "The drake joins before the hunter is ready.",
        feature_choices:,
        companion_name: "Cinder",
        companion_size: "Large"
      )
    end
    assert_match(/Large companion requires level 3/, error.message)
    assert_equal "Shadowpath", below_minimum.reload.subclass_name
  end

  test "the approval service rejects blank, overlong, stale, same, and non-story choices without changing the sheet" do
    inputs = [
      { current_subclass: "Oath of Refuge", to_subclass: "Oathbreaker", story_note: "  " },
      { current_subclass: "Oath of Refuge", to_subclass: "Oathbreaker", story_note: "x" * 1_001 },
      { current_subclass: "Oath of Vengeance", to_subclass: "Oathbreaker", story_note: "Stale form." },
      { current_subclass: "Oath of Refuge", to_subclass: "Oath of Refuge", story_note: "No replacement." },
      { current_subclass: "Oath of Refuge", to_subclass: "Oath of Vengeance", story_note: "Ordinary subclass." }
    ]

    inputs.each do |attributes|
      assert_raises(ArgumentError) do
        StorySubclassChangeService.call(
          character: @character,
          share: @share,
          approved_by: @gm,
          **attributes
        )
      end
    end

    assert_equal "Oath of Refuge", @character.reload.subclass_name
    assert_empty @character.story_subclass_changes
  end

  test "a story-only subclass cannot be assigned directly without a GM audit record" do
    character = @character.dup
    character.assign_attributes(name: "Unaudited story change", subclass_name: "Oathbreaker")

    assert_not character.valid?
    assert_includes character.errors[:subclass_name], "requires a GM-approved story change with a story note"
  end

  private
    def create_oathsworn
      character = Character.create!(
        name: "Oathbound Hero",
        account: @owner,
        character_class: CharacterClass.find_by!(name: "Oathsworn"),
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        stat_array: "standard",
        skill_set_attributes: { might: 7 }
      )
      character.finalize_creation!
      character.update_columns(level: 3, status: "playable", subclass_name: "Oath of Refuge")
      character.skill_set.update!(might: 9)
      character
    end

    def create_commander
      character = Character.create!(
        name: "Spellblade Candidate",
        account: @owner,
        character_class: CharacterClass.find_by!(name: "Commander"),
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        stat_array: "standard",
        language_choices: [ "Draconic", "Primordial" ],
        skill_set_attributes: { might: 7 }
      )
      character.finalize_creation!
      character.update_columns(level: 3, status: "playable", subclass_name: "Champion of the Bulwark")
      character.skill_set.update!(might: 9)
      character
    end

    def create_shadowmancer
      character = Character.create!(
        name: "Reaver Candidate",
        account: @owner,
        character_class: CharacterClass.find_by!(name: "Shadowmancer"),
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        stat_array: "standard",
        language_choices: [ "Elvish", "Draconic" ],
        skill_set_attributes: { stealth: 7 }
      )
      character.finalize_creation!
      character.update_columns(
        level: 3,
        status: "playable",
        subclass_name: "Pact of the Red Dragon",
        feature_choices: { "Lesser Shadow Invocation" => { "3" => [ "Whispers of the Grave" ] } }
      )
      character.skill_set.update!(stealth: 9)
      character
    end

    def create_hunter
      character = Character.create!(
        name: "Beastmaster Candidate",
        account: @owner,
        character_class: CharacterClass.find_by!(name: "Hunter"),
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        stat_array: "standard",
        skill_set_attributes: { finesse: 7 }
      )
      character.finalize_creation!
      character.update_columns(
        level: 3,
        status: "playable",
        subclass_name: "Shadowpath",
        feature_choices: { "Thrill of the Hunt" => { "2" => [ "Fleet Feet", "Wild Instinct" ] } }
      )
      character.skill_set.update!(finesse: 9)
      character
    end
end
