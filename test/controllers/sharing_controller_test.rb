require "test_helper"

# S-04:AC-4 S-08:AC-1 S-08:AC-2 S-08:AC-3 S-08:AC-4 S-08:AC-5 S-08:AC-6 S-09:AC-1 S-09:AC-3
class SharingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @player = Account.create!(display_name: "Player One", email: "player-#{SecureRandom.hex(4)}@example.com")
    @gm = Account.create!(display_name: "Game Master", email: "gm-#{SecureRandom.hex(4)}@example.com", role: "gm")
    @campaign = Campaign.create!(owner_account: @gm, name: "The Shared Road")
    @campaign.campaign_memberships.create!(account: @gm, role: "gm")
    @campaign.campaign_memberships.create!(account: @player, role: "player")
    @character = Character.create!(name: "Shared Hero", account: @player)
  end

  test "a player can share a read-only sheet without transferring ownership" do
    sign_in(@player)

    assert_difference("CharacterShare.count") do
      post character_shares_url(@character), params: { campaign_id: @campaign.id }
    end

    assert_redirected_to character_url(@character)
    share = @character.character_shares.order(:id).last
    assert_equal @player, @character.reload.account
    assert_equal "read", share.permission

    get shared_character_url(share.share_token)

    assert_response :success
    assert_includes response.body, "Shared Hero"
    assert_includes response.body, "Read-only shared sheet"
  end

  test "the read-only shared sheet includes structured inventory without edit controls" do
    @character.inventory_items.create!(name: "2 potions", slots: 1)
    @character.update!(current_gold: 150)
    sign_in(@player)
    post character_shares_url(@character), params: { campaign_id: @campaign.id }
    share = @character.character_shares.order(:id).last

    get shared_character_url(share.share_token)

    assert_response :success
    assert_includes response.body, "Inventory"
    assert_includes response.body, "2 potions"
    assert_includes response.body, "150 gp"
    assert_includes response.body, "Core Rules 2.0.1, p. 21"
    assert_select ".inventory-item-row form", 0
  end

  # S-02:AC-1 S-02:AC-2 S-08:AC-2 S-09:AC-3
  test "the read-only shared sheet derives conditions from current HP and Wounds" do
    @character.trait_set.update!(max_hp: 10, current_hp: 5, max_wounds: 6, current_wounds: 1)
    sign_in(@player)
    post character_shares_url(@character), params: { campaign_id: @campaign.id }
    share = @character.character_shares.order(:id).last

    get shared_character_url(share.share_token)

    assert_response :success
    assert_select ".derived-condition-chip", text: "Bloodied"
    assert_select ".derived-condition-chip", text: "Wounded"
    assert_includes response.body, "Core Rules 2.0.1, p. 11"
    assert_includes response.body, "Derived · read-only"
  end

  # S-05:AC-1 S-05:AC-2 S-08:AC-1 S-08:AC-3 S-09:AC-1 S-09:AC-3
  test "the read-only shared sheet shows class starting gear and the unitemized background-gear notice" do
    Rails.application.load_seed
    starting_character = Character.create!(
      name: "Starting Gear Share",
      account: @player,
      character_class: CharacterClass.find_by!(name: "Berserker"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    sign_in(@player)
    post character_shares_url(starting_character), params: { campaign_id: @campaign.id }
    share = starting_character.character_shares.order(:id).last

    get shared_character_url(share.share_token)

    assert_response :success
    assert_includes response.body, "Battleaxe, Rations (meat), Rope (50 ft.)"
    assert_includes response.body, "Starting kit carried"
    assert_includes response.body, "Battleaxe"
    assert_includes response.body, "Core Rules 2.0.1, pp. 21, 34"
    assert_includes response.body, "The Core Rules include background equipment with class gear"
    assert_includes response.body, "Core Rules 2.0.1, p. 20"
  end

  test "a GM can inspect a shared sheet from the campaign workspace" do
    sign_in(@player)
    post character_shares_url(@character), params: { campaign_id: @campaign.id }
    share = @character.character_shares.order(:id).last

    sign_in(@gm)
    get campaign_url(@campaign)

    assert_response :success
    assert_includes response.body, "The Shared Road"
    assert_includes response.body, "Shared Hero"
    assert_includes response.body, "Read-only"
    assert_includes response.body, shared_character_path(share.share_token)
  end

  # S-02:AC-4 S-08:AC-4
  test "only the shared campaign GM can replace a subclass with a story-based option and the sheet records it" do
    character = create_story_character
    sign_in(@player)
    post character_shares_url(character), params: { campaign_id: @campaign.id }
    share = character.character_shares.order(:id).last

    sign_in(@gm)
    get shared_character_url(share.share_token)
    assert_response :success
    assert_includes response.body, "Shared sheet · limited GM action"
    assert_select "form[action='#{shared_story_subclass_changes_path(share.share_token)}'] select[name='story_subclass_change[to_subclass]'] option", text: "Oathbreaker"
    assert_select "textarea[name='story_subclass_change[story_note]'][required]"
    assert_select ".story-subclass-panel form", 1
    assert_select ".tracker-form", 0
    assert_select ".inventory-item-row form", 0

    assert_difference("StorySubclassChange.count", 1) do
      assert_difference("CharacterRevision.where(event_type: 'story_subclass_change').count", 1) do
        post shared_story_subclass_changes_url(share.share_token), params: {
          story_subclass_change: {
            current_subclass: "Oath of Refuge",
            to_subclass: "Oathbreaker",
            story_note: "She breaks the oath to save the refugees."
          }
        }
      end
    end

    assert_redirected_to shared_character_url(share.share_token)
    assert_equal "Oathbreaker", character.reload.subclass_name
    assert_equal "read", share.reload.permission
    change = character.story_subclass_changes.sole
    assert_equal @gm, change.approved_by_account
    assert_equal @campaign, change.campaign
    assert_includes response.location, share.share_token

    sign_in(@player)
    get shared_character_url(share.share_token)
    assert_response :success
    assert_select ".story-subclass-history", /Oath of Refuge → Oathbreaker/
    assert_select ".story-subclass-entry", /She breaks the oath to save the refugees\./
    assert_select ".story-subclass-entry", /Heroes 2\.0\.1, p\. 73/
    assert_select "form[action='#{shared_story_subclass_changes_path(share.share_token)}']", 0
  end

  # S-08:AC-4 S-09:AC-3
  test "a GM cannot use owner-only encounter controls on a shared character" do
    character = create_story_character
    sign_in(@player)
    post character_shares_url(character), params: { campaign_id: @campaign.id }
    sign_in(@gm)

    original_hp = character.trait_set.current_hp
    patch game_feature_character_url(character), params: { game_feature: { action: "summon_bonescythe" } }

    assert_redirected_to character_url(character)
    assert_equal "Only the player who owns this character can edit it.", flash[:alert]
    assert_equal original_hp, character.reload.trait_set.current_hp
    assert_not character.reload.bonescythe_summoned?
    assert_empty character.character_revisions.where(event_type: "weapon_summoned")
  end

  # S-02:AC-1 S-02:AC-2 S-08:AC-4 S-09:AC-1 S-09:AC-3
  test "the GM-approved Reaver change records patron powers replaced on the read-only shared sheet" do
    character = create_shadowmancer
    character.spells << Spell.find_by!(name: "Shadow Blast")
    tracks = character.trait_set.resource_tracks.map do |track|
      track.fetch("key") == "pilfered_power" ? track.merge("current" => 1) : track
    end
    character.trait_set.update!(resource_tracks: tracks)

    sign_in(@player)
    post character_shares_url(character), params: { campaign_id: @campaign.id }
    share = character.character_shares.order(:id).last
    sign_in(@gm)

    get shared_character_url(share.share_token)
    assert_response :success
    assert_select "select[name='story_subclass_change[to_subclass]'] option", text: "Reaver"
    assert_select ".tracker-form", 0

    assert_difference("StorySubclassChange.count", 1) do
      post shared_story_subclass_changes_url(share.share_token), params: {
        story_subclass_change: {
          current_subclass: "Pact of the Red Dragon",
          to_subclass: "Reaver",
          story_note: "The patron abandons the hero and leaves a bone-forged weapon."
        }
      }
    end

    assert_redirected_to shared_character_url(share.share_token)
    assert_equal "Reaver", character.reload.subclass_name
    assert_not character.spells.exists?(name: "Shadow Blast")
    change = character.story_subclass_changes.sole
    assert_equal "The patron abandons the hero and leaves a bone-forged weapon.", change.story_note
    assert_equal "1 / 2", change.subclass_choice_entries.find { |entry| entry.fetch(:label) == "Replaced resource · Pilfered Power" }.fetch(:value)
    assert_equal [ "Heroes 2.0.1, p. 78" ], change.subclass_choice_entries.find { |entry| entry.fetch(:label) == "No longer castable" }.fetch(:source_refs)

    get shared_character_url(share.share_token)
    assert_response :success
    assert_includes response.body, "Replaced resource · Pilfered Power"
    assert_includes response.body, "Heroes 2.0.1, p. 44"
    assert_includes response.body, "The patron abandons the hero and leaves a bone-forged weapon."
    assert_select ".tracker-form", 0
  end

  test "the GM story-change form collects and publishes Spellblade's earned spell choices" do
    character = create_commander_story_character
    sign_in(@player)
    post character_shares_url(character), params: { campaign_id: @campaign.id }
    share = character.character_shares.order(:id).last

    sign_in(@gm)
    get shared_character_url(share.share_token)

    assert_response :success
    assert_select "select[name='story_subclass_change[spell_choices][Deep Knowledge · tiered spell][3]'][required] option[value='Flame Dart']"
    assert_select "select[name='story_subclass_change[spell_choices][Deep Knowledge · Utility Spell][3]'][required] option[value='Firebrand']"
    assert_select ".story-subclass-panel", /Heroes 2\.0\.1, p\. 76/

    post shared_story_subclass_changes_url(share.share_token), params: {
      story_subclass_change: {
        current_subclass: "Champion of the Bulwark",
        to_subclass: "Spellblade",
        story_note: "The commander binds their tactics to a spellblade tradition.",
        spell_choices: {
          "Deep Knowledge · tiered spell" => { "3" => "Flame Dart" },
          "Deep Knowledge · Utility Spell" => { "3" => "Firebrand" }
        }
      }
    }

    assert_redirected_to shared_character_url(share.share_token)
    assert_equal "Spellblade", character.reload.subclass_name
    assert_equal [ "Flame Dart" ], character.recorded_spell_choices.fetch("Deep Knowledge · tiered spell")

    sign_in(@player)
    get shared_character_url(share.share_token)
    assert_response :success
    assert_select ".story-subclass-choice", /Level 3 · Deep Knowledge · tiered spell: Flame Dart/
    assert_select ".spell-chip", text: "Flame Dart"
  end

  test "the GM story-change form records Beastmaster's companion and first two Hunt choices" do
    character = create_hunter_story_character
    sign_in(@player)
    post character_shares_url(character), params: { campaign_id: @campaign.id }
    share = character.character_shares.order(:id).last

    sign_in(@gm)
    get shared_character_url(share.share_token)

    assert_response :success
    assert_select "select[name='story_subclass_change[companion_size]'][required] option", text: "Small"
    assert_select "input[name='story_subclass_change[companion_name]'][required][maxlength='80']"
    assert_select "select[name='story_subclass_change[feature_choices][Thrill of the Hunt][2][]'][multiple][required] option[value='Go for the Throat!']"
    assert_select "select[name='story_subclass_change[feature_choices][Thrill of the Hunt][2][]'][multiple][required] option[value='Protect Me!']"

    post shared_story_subclass_changes_url(share.share_token), params: {
      story_subclass_change: {
        current_subclass: "Shadowpath",
        to_subclass: "Beastmaster",
        story_note: "A rescued hawk refuses to leave the hunter's side.",
        companion_size: "Small",
        companion_name: "Ember",
        feature_choices: {
          "Thrill of the Hunt" => { "2" => [ "Go for the Throat!", "Protect Me!" ] }
        }
      }
    }

    assert_redirected_to shared_character_url(share.share_token)
    assert_equal "Beastmaster", character.reload.subclass_name
    assert_equal [ "Go for the Throat!", "Protect Me!" ], character.recorded_feature_choices.fetch("Thrill of the Hunt")
    assert_equal({ "size" => "Small", "name" => "Ember" }, character.subclass_choices.fetch("companion"))

    sign_in(@player)
    get shared_character_url(share.share_token)
    assert_response :success
    assert_select ".story-subclass-choice", /Companion: Small Ember.*Heroes 2\.0\.1, p\. 80/
    assert_select ".story-subclass-choice", /Go for the Throat!.*Protect Me!.*Heroes 2\.0\.1, p\. 28.*Heroes 2\.0\.1, p\. 80/
    assert_select ".progression-entry", /Companion.*Ember.*Small animal.*Heroes 2\.0\.1, p\. 80/
    assert_select ".progression-entry", /Keen Eyes.*Mark a target for free.*1 \/ 1 per encounter/
    assert_select ".progression-entry", /Go for the Throat!.*1 Thrill of the Hunt charge.*Heroes 2\.0\.1, p\. 80/
    assert_select ".resource-summary-item", /Protect Me! · uses.*1.*Encounter ends/
    assert_select ".tracker-form", 0
  end

  test "shared players and global GMs without GM membership cannot approve story subclass changes" do
    character = create_story_character
    sign_in(@player)
    post character_shares_url(character), params: { campaign_id: @campaign.id }
    share = character.character_shares.order(:id).last

    get shared_character_url(share.share_token)
    assert_response :success
    assert_select "form[action='#{shared_story_subclass_changes_path(share.share_token)}']", 0

    assert_no_difference("StorySubclassChange.count") do
      post shared_story_subclass_changes_url(share.share_token), params: {
        story_subclass_change: {
          current_subclass: "Oath of Refuge",
          to_subclass: "Oathbreaker",
          story_note: "Unauthorized."
        }
      }
    end
    assert_response :forbidden
    assert_equal "Oath of Refuge", character.reload.subclass_name

    campaign_player_with_global_gm_role = Account.create!(display_name: "Wrong Campaign Role", email: "wrong-role-#{SecureRandom.hex(4)}@example.com", role: "gm")
    @campaign.campaign_memberships.create!(account: campaign_player_with_global_gm_role, role: "player")
    sign_in(campaign_player_with_global_gm_role)
    post shared_story_subclass_changes_url(share.share_token), params: {
      story_subclass_change: {
        current_subclass: "Oath of Refuge",
        to_subclass: "Oathbreaker",
        story_note: "A global role is not campaign approval."
      }
    }

    assert_response :forbidden
    assert_equal "Oath of Refuge", character.reload.subclass_name
  end

  test "a GM cannot approve a blank story note or target a non-story subclass" do
    character = create_story_character
    sign_in(@player)
    post character_shares_url(character), params: { campaign_id: @campaign.id }
    share = character.character_shares.order(:id).last
    sign_in(@gm)

    assert_no_difference("StorySubclassChange.count") do
      post shared_story_subclass_changes_url(share.share_token), params: {
        story_subclass_change: {
          current_subclass: "Oath of Refuge",
          to_subclass: "Oathbreaker",
          story_note: "   "
        }
      }
    end
    assert_redirected_to shared_character_url(share.share_token)
    assert_match(/story note/i, flash[:alert])

    assert_no_difference("StorySubclassChange.count") do
      post shared_story_subclass_changes_url(share.share_token), params: {
        story_subclass_change: {
          current_subclass: "Oath of Refuge",
          to_subclass: "Oath of Vengeance",
          story_note: "A normal subclass is not eligible."
        }
      }
    end
    assert_equal "Oath of Refuge", character.reload.subclass_name
  end

  test "a shared rules-backed sheet includes unlocked class progression" do
    Rails.application.load_seed
    progression_character = Character.create!(
      name: "Progression Share",
      account: @player,
      character_class: CharacterClass.find_by!(name: "Berserker"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      level: 4,
      feature_choices: { "Savage Arsenal" => [ "Death Blow" ] }
    )
    sign_in(@player)
    post character_shares_url(progression_character), params: { campaign_id: @campaign.id }
    share = progression_character.character_shares.order(:id).last

    get shared_character_url(share.share_token)

    assert_response :success
    assert_includes response.body, "Features unlocked"
    assert_includes response.body, "Rage"
    assert_includes response.body, "Death Blow"
    assert_includes response.body, "Heroes 2.0.1"
  end

  test "a non-member cannot open a campaign workspace" do
    outsider = Account.create!(display_name: "Outsider", email: "outsider-#{SecureRandom.hex(4)}@example.com")
    sign_in(outsider)

    get campaign_url(@campaign)

    assert_redirected_to campaigns_url
    assert_includes flash[:alert], "campaign access"
  end

  test "a GM cannot create a share on a player-owned character" do
    sign_in(@gm)

    assert_no_difference("CharacterShare.count") do
      post character_shares_url(@character), params: { campaign_id: @campaign.id }
    end

    assert_redirected_to character_url(@character)
    assert_includes flash[:alert], "Only the character owner"
  end

  test "a GM cannot edit or level up a player-owned character" do
    sign_in(@gm)

    get edit_character_url(@character)
    assert_redirected_to character_url(@character)
    assert_includes flash[:alert], "Only the player who owns"

    get new_character_level_up_url(@character)
    assert_redirected_to character_url(@character)
    assert_includes flash[:alert], "Only the player who owns"
  end

  test "a player can join a campaign with its invite code" do
    second_player = Account.create!(display_name: "Second Player", email: "second-#{SecureRandom.hex(4)}@example.com")
    sign_in(second_player)

    post join_campaign_by_code_url, params: { invite_code: @campaign.invite_code }

    assert_redirected_to campaign_url(@campaign)
    assert @campaign.campaign_memberships.exists?(account: second_player)
  end

  test "leaving a campaign revokes the player's shared sheets" do
    sign_in(@player)
    post character_shares_url(@character), params: { campaign_id: @campaign.id }
    share = @character.character_shares.order(:id).last

    assert_difference("CharacterShare.count", -1) do
      delete leave_campaign_url(@campaign)
    end

    assert_redirected_to campaigns_url
    assert_not CharacterShare.exists?(share.id)
    assert_not @campaign.campaign_memberships.exists?(account: @player)

    sign_in(@gm)
    get shared_character_url(share.share_token)
    assert_response :not_found
  end

  private
    def create_story_character
      Rails.application.load_seed unless CharacterClass.exists?(name: "Oathsworn")
      character = Character.create!(
        name: "Shared Oathbound Hero",
        account: @player,
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

    def create_commander_story_character
      Rails.application.load_seed unless CharacterClass.exists?(name: "Commander")
      character = Character.create!(
        name: "Shared Spellblade Candidate",
        account: @player,
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
      Rails.application.load_seed unless CharacterClass.exists?(name: "Shadowmancer")
      character = Character.create!(
        name: "Shared Reaver Candidate",
        account: @player,
        character_class: CharacterClass.find_by!(name: "Shadowmancer"),
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        stat_array: "standard",
        language_choices: [ "Elvish", "Draconic" ],
        skill_set_attributes: { stealth: 7 }
      )
      character.finalize_creation!
      character.update_columns(level: 3, status: "playable", subclass_name: "Pact of the Red Dragon")
      character.skill_set.update!(stealth: 9)
      character
    end

    def create_hunter_story_character
      Rails.application.load_seed unless CharacterClass.exists?(name: "Hunter")
      character = Character.create!(
        name: "Shared Beastmaster Candidate",
        account: @player,
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

    def sign_in(account)
      post sessions_url, params: { account: { display_name: account.display_name, email: account.email, role: account.role } }
      assert_redirected_to characters_url
    end
end
