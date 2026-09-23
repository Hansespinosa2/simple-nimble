class CharacterClass < ApplicationRecord
  FALLBACK_STAT_INCREASES = {
    "key" => [ 4, 8, 12, 16 ],
    "secondary" => [ 5, 9, 13, 17 ],
    "any_two" => [ 20 ]
  }.freeze

  # Structured rules-canon slice (spec 02): only the fields needed to derive
  # a legal starting character (spec 05). Intentionally seeded with 2 of the
  # 11 Nimble classes for a minimal-but-real vertical slice, not the full
  # class corpus.
  has_many :characters, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :key_stat_one, :key_stat_two, presence: true, inclusion: { in: %w[strength dexterity intelligence will] }
  validates :save_bonus_stat, :save_penalty_stat, inclusion: { in: %w[strength dexterity intelligence will] }, allow_nil: true
  validates :hit_die, presence: true
  validates :starting_hp, presence: true, numericality: { greater_than: 0 }
  validate :key_stats_are_distinct

  def key_stats
    [ key_stat_one, key_stat_two ]
  end

  def secondary_stats
    %w[strength dexterity intelligence will] - key_stats
  end

  def rules_entry
    Rules::NimbleCatalog.class_for(name)
  end

  def source_reference
    rules_entry&.fetch("source_ref") || "Nimble v2.0.1 · Heroes"
  end

  def spell_schools
    rules_entry.to_h.fetch("spell_schools", [])
  end

  def spell_tier_for(level)
    Rules::NimbleCatalog.spell_tier_for(name, level)
  end

  def stat_increase_type_for(level)
    Rules::NimbleCatalog.stat_increase_for(name, level) || fallback_stat_increase_type_for(level)
  end

  def stat_options_for(type)
    case type
    when "key" then key_stats
    when "secondary" then secondary_stats
    when "any_two" then Character::STAT_NAMES
    else []
    end
  end

  def resource_rules
    rules_entry.to_h.fetch("resource", {})
  end

  private
    def fallback_stat_increase_type_for(level)
      FALLBACK_STAT_INCREASES.each do |type, levels|
        return type if levels.include?(level.to_i)
      end

      nil
    end

    def key_stats_are_distinct
      return if key_stat_one.blank? || key_stat_two.blank? || key_stat_one != key_stat_two

      errors.add(:key_stat_two, "must be different from the first key stat")
    end
end
