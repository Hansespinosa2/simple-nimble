class RulesetVersion < ApplicationRecord
  has_many :characters, dependent: :nullify

  validates :name, :version, presence: true
  validates :version, uniqueness: { scope: :name }

  scope :active, -> { where(active: true) }

  def label
    "#{name} #{version}"
  end
end
