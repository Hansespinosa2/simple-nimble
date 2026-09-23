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
    def sign_in(account)
      post sessions_url, params: { account: { display_name: account.display_name, email: account.email, role: account.role } }
      assert_redirected_to characters_url
    end
end
