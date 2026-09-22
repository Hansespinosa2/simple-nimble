class Account < ApplicationRecord
  has_many :characters, dependent: :nullify
  has_many :owned_campaigns, class_name: "Campaign", foreign_key: :owner_account_id, dependent: :destroy
  has_many :campaign_memberships, dependent: :destroy
  has_many :campaigns, through: :campaign_memberships
  has_many :created_character_shares, class_name: "CharacterShare", foreign_key: :created_by_account_id, dependent: :nullify

  before_validation :ensure_session_token, on: :create

  validates :display_name, presence: true, length: { maximum: 80 }
  validates :role, inclusion: { in: %w[player gm] }
  validates :email, uniqueness: true, allow_blank: true

  def gm?
    role == "gm"
  end

  private
    def ensure_session_token
      self.session_token ||= SecureRandom.hex(24)
    end
end
