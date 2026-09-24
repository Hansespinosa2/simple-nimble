require "test_helper"

# S-02:AC-4 S-08:AC-4 S-09:AC-1
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
    share = commander.character_shares.create!(campaign: @campaign, created_by_account: @owner, permission: "read")

    StorySubclassChangeService.call(
      character: commander,
      share:,
      approved_by: @gm,
      current_subclass: "Champion of the Bulwark",
      to_subclass: "Spellblade",
      story_note: "An alliance with the fire cult changed the commander's path."
    )

    commander.reload
    assert_equal "Spellblade", commander.subclass_name
    assert_equal [], commander.language_choices
    assert_equal "Common, Dwarvish, Draconic, Primordial", commander.languages
    assert_includes commander.creation_issues.map { |issue| issue.fetch(:message) }, "Choose 2 more languages for your INT."
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
end
