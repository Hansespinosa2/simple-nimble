class LevelUp < ApplicationRecord
  require "securerandom"

  belongs_to :character

  serialize :preview, coder: JSON
  serialize :feature_choices, coder: JSON

  STAT_NAMES = %w[strength dexterity intelligence will].freeze
  SKILL_NAMES = %w[arcana examination finesse influence insight lore might naturecraft perception stealth].freeze

  validates :from_level, :to_level, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: %w[draft finalized] }
  validates :skill_name, inclusion: { in: SKILL_NAMES }, allow_blank: true
  validates :skill_from, inclusion: { in: SKILL_NAMES }, allow_blank: true
  validates :stat_name, inclusion: { in: STAT_NAMES }, allow_blank: true
  validates :second_stat_name, inclusion: { in: STAT_NAMES }, allow_blank: true
  validates :subclass_name, length: { maximum: 120 }, allow_blank: true
  validates :hit_die_roll_one, :hit_die_roll_two, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def draft?
    status == "draft"
  end

  def finalized?
    status == "finalized"
  end

  def roll_hit_die!(sides)
    self.hit_die_roll_one = SecureRandom.random_number(sides) + 1
    self.hit_die_roll_two = SecureRandom.random_number(sides) + 1
  end
end
