class Background < ApplicationRecord
  # Structured rules-canon slice (spec 02): seeded with 2 of the ~24 Nimble
  # backgrounds, one of them deliberately prerequisite-gated so the
  # creation-flow legality check (spec 05 TBD-1) has a real case to enforce.
  has_many :characters, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :prerequisite_stat, inclusion: { in: %w[strength dexterity intelligence will] }, allow_nil: true
  validates :prerequisite_max, presence: true, numericality: { only_integer: true }, if: :prerequisite_stat?

  # A background's stat prerequisite (e.g. "So Dumb I'm Smart Sometimes"
  # requires INT <= 0) is checked at character-creation finalization, not on
  # every stat change.
  def satisfied_by?(stat_set)
    return true if prerequisite_stat.blank?
    return false if stat_set.nil?

    stat_set.public_send(prerequisite_stat) <= prerequisite_max
  end
end
