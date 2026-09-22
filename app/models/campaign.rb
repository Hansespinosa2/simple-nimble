class Campaign < ApplicationRecord
  belongs_to :owner_account, class_name: "Account"
  has_many :campaign_memberships, dependent: :destroy
  has_many :accounts, through: :campaign_memberships
  has_many :character_shares, dependent: :destroy
  has_many :characters, through: :character_shares

  before_validation :ensure_invite_code, on: :create

  validates :name, presence: true, length: { maximum: 100 }

  def member?(account)
    account.present? && (owner_account_id == account.id || campaign_memberships.exists?(account_id: account.id))
  end

  private
    def ensure_invite_code
      self.invite_code ||= SecureRandom.alphanumeric(8).upcase
    end
end
