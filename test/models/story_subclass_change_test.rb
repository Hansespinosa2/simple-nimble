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
    original_revision_count = @character.character_revisions.count

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
    assert_equal 8, @character.trait_set.max_wounds
    assert_equal 2, @character.trait_set.current_wounds
    assert_equal 7, @character.trait_set.current_hp
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
    assert_equal spell_choices.transform_values { |by_level| by_level.transform_values { |spell| [ spell ] } }, change.subclass_choices
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
end
