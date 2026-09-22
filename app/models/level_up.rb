class LevelUp < ApplicationRecord
  belongs_to :character

  serialize :preview, coder: JSON

  STAT_NAMES = %w[strength dexterity intelligence will].freeze
  SKILL_NAMES = %w[arcana examination finesse influence insight lore might naturecraft perception stealth].freeze

  validates :from_level, :to_level, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: %w[draft finalized] }
  validates :skill_name, inclusion: { in: SKILL_NAMES }, allow_blank: true
  validates :stat_name, inclusion: { in: STAT_NAMES }, allow_blank: true

  def draft?
    status == "draft"
  end

  def finalized?
    status == "finalized"
  end
end
