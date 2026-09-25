class CharacterSharesController < ApplicationController
  before_action :require_account
  before_action :set_character

  def create
    campaign = Campaign.find(params.expect(:campaign_id))
    unless campaign.member?(current_account)
      redirect_to @character, alert: "Only the character owner can share this sheet to a campaign."
      return
    end

    share = @character.character_shares.find_or_initialize_by(campaign: campaign)
    share.assign_attributes(created_by_account: current_account, permission: "read")
    share.save!
    redirect_to @character, notice: "Shared with #{campaign.name}. Read-only link ready."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to @character, alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    share = @character.character_shares.find(params.expect(:id))
    if share.created_by_account == current_account || @character.account == current_account
      share.destroy!
      redirect_to @character, notice: "Campaign access revoked."
    else
      redirect_to @character, alert: "Only the character owner can revoke this share."
    end
  end

  private
    def set_character
      @character = current_account.characters.find(params.expect(:character_id))
    end
end
