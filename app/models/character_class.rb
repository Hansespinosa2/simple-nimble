class CharacterClass < ApplicationRecord
  # Structured rules-canon slice (spec 02): only the fields needed to derive
  # a legal starting character (spec 05). Intentionally seeded with 2 of the
  # 11 Nimble classes for a minimal-but-real vertical slice, not the full
  # class corpus.
  has_many :characters, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :key_stat_one, :key_stat_two, presence: true, inclusion: { in: %w[strength dexterity intelligence will] }
  validates :hit_die, presence: true
  validates :starting_hp, presence: true, numericality: { greater_than: 0 }

  def key_stats
    [ key_stat_one, key_stat_two ]
  end

  def secondary_stats
    %w[strength dexterity intelligence will] - key_stats
  end
end
