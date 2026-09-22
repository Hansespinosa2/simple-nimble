class CampaignMembership < ApplicationRecord
  belongs_to :campaign
  belongs_to :account

  validates :role, inclusion: { in: %w[player gm] }
  validates :account_id, uniqueness: { scope: :campaign_id }
end
