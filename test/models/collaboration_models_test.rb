require "test_helper"

# S-03:AC-1 S-03:AC-3 S-03:AC-4 S-08:AC-1 S-08:AC-3 S-09:AC-3
class CollaborationModelsTest < ActiveSupport::TestCase
  test "accounts generate stable session identities and enforce roles" do
    player = Account.create!(display_name: "Player", email: "player-#{SecureRandom.hex(4)}@example.com")
    gm = Account.create!(display_name: "GM", email: "gm-#{SecureRandom.hex(4)}@example.com", role: "gm")

    assert player.session_token.present?
    assert_not_equal player.session_token, gm.session_token
    assert_not player.gm?
    assert gm.gm?
    assert_not Account.new(display_name: "Imposter", role: "admin").valid?
  end

  test "campaign membership distinguishes owners, members, and outsiders" do
    owner = Account.create!(display_name: "Owner", email: "owner-#{SecureRandom.hex(4)}@example.com")
    member = Account.create!(display_name: "Member", email: "member-#{SecureRandom.hex(4)}@example.com")
    outsider = Account.create!(display_name: "Outsider", email: "outsider-#{SecureRandom.hex(4)}@example.com")
    campaign = Campaign.create!(owner_account: owner, name: "Model Campaign")
    campaign.campaign_memberships.create!(account: owner, role: "gm")
    campaign.campaign_memberships.create!(account: member, role: "player")

    assert campaign.invite_code.present?
    assert_equal 8, campaign.invite_code.length
    assert campaign.member?(owner)
    assert campaign.member?(member)
    assert_not campaign.member?(outsider)
    assert_not campaign.campaign_memberships.build(account: member).valid?
  end

  test "a character share is read-only, unique per campaign, and has a public path" do
    owner = Account.create!(display_name: "Share Owner", email: "share-owner-#{SecureRandom.hex(4)}@example.com")
    campaign = Campaign.create!(owner_account: owner, name: "Share Campaign")
    character = Character.create!(name: "Shared Model Hero", account: owner)
    share = CharacterShare.create!(character:, campaign:, created_by_account: owner, permission: "read")

    assert share.share_token.present?
    assert_match %r{/shared/#{Regexp.escape(share.share_token)}\z}, share.public_path
    assert_not CharacterShare.new(character:, campaign:, permission: "write").valid?
    assert_not CharacterShare.new(character:, campaign:, permission: "read").valid?
  end

  test "revisions retain event labels and the snapshot that was recorded" do
    character = Character.create!(name: "Revision Hero")
    revision = character.record_revision!(event_type: "game_update", summary: "Changed HP", from_level: 1, to_level: 1)

    assert_equal "Game update", revision.event_label
    assert_equal "Changed HP", revision.summary
    assert_equal character.name, revision.snapshot.dig("character", "name")
    assert_equal character.trait_set.max_hp, revision.snapshot.dig("traits", "max_hp")
  end
end
