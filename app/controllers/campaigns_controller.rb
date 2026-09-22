class CampaignsController < ApplicationController
  before_action :require_account
  before_action :set_campaign, only: %i[show join leave]

  def index
    @campaigns = Campaign.where(owner_account: current_account).or(
      Campaign.joins(:campaign_memberships).where(campaign_memberships: { account_id: current_account.id })
    ).distinct.order(:name)
  end

  def new
    @campaign = current_account.owned_campaigns.build
  end

  def create
    @campaign = current_account.owned_campaigns.build(campaign_params)
    if @campaign.save
      @campaign.campaign_memberships.create!(account: current_account, role: "gm")
      redirect_to @campaign, notice: "Campaign created. Share its invite code with your table."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    unless @campaign.member?(current_account)
      redirect_to campaigns_path, alert: "You need campaign access to view this workspace."
      return
    end

    @shares = @campaign.character_shares.includes(:character, :created_by_account).order(created_at: :desc)
  end

  def join
    if params[:invite_code].to_s.upcase == @campaign.invite_code
      @campaign.campaign_memberships.find_or_create_by!(account: current_account) { |membership| membership.role = current_account.role }
      redirect_to @campaign, notice: "You joined #{@campaign.name}."
    else
      redirect_to campaigns_path, alert: "That invite code does not match this campaign."
    end
  end

  def leave
    membership = @campaign.campaign_memberships.find_by(account: current_account)
    membership&.destroy!
    @campaign.character_shares.joins(:character).where(characters: { account_id: current_account.id }).destroy_all
    redirect_to campaigns_path, notice: "You left #{@campaign.name}. Shared access is revoked."
  end

  private
    def require_account
      return if current_account.present?

      redirect_to new_session_path, alert: "Create a workspace profile before using campaigns."
    end

    def set_campaign
      @campaign = Campaign.find(params.expect(:id))
    end

    def campaign_params
      params.expect(campaign: [ :name, :description ])
    end
end
