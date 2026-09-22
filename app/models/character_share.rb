class CharacterShare < ApplicationRecord
  belongs_to :character
  belongs_to :campaign
  belongs_to :created_by_account, class_name: "Account", optional: true

  before_validation :ensure_share_token, on: :create

  validates :permission, inclusion: { in: %w[read] }
  validates :character_id, uniqueness: { scope: :campaign_id }

  def public_path
    Rails.application.routes.url_helpers.shared_character_path(share_token)
  end

  private
    def ensure_share_token
      self.share_token ||= SecureRandom.urlsafe_base64(18)
    end
end
