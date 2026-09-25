class Account < ApplicationRecord
  has_secure_password

  has_many :characters, dependent: :nullify
  has_many :owned_campaigns, class_name: "Campaign", foreign_key: :owner_account_id, dependent: :destroy
  has_many :campaign_memberships, dependent: :destroy
  has_many :campaigns, through: :campaign_memberships
  has_many :created_character_shares, class_name: "CharacterShare", foreign_key: :created_by_account_id, dependent: :nullify
  has_many :approved_story_subclass_changes, class_name: "StorySubclassChange", foreign_key: :approved_by_account_id, dependent: :restrict_with_error

  before_validation :ensure_session_token, on: :create

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :display_name, presence: true, length: { maximum: 80 }
  validates :email, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: 12 }, if: -> { password.present? }
  validates :password_confirmation, presence: true, on: :create

  private
    def ensure_session_token
      self.session_token ||= SecureRandom.hex(24)
    end
end
