require "test_helper"

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

  test "a GM cannot create a share on a player-owned character" do
    sign_in(@gm)

    assert_no_difference("CharacterShare.count") do
      post character_shares_url(@character), params: { campaign_id: @campaign.id }
    end

    assert_redirected_to character_url(@character)
    assert_includes flash[:alert], "Only the character owner"
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
  end

  private
    def sign_in(account)
      post sessions_url, params: { account: { display_name: account.display_name, email: account.email, role: account.role } }
      assert_redirected_to characters_url
    end
end
