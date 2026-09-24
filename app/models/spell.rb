class Spell < ApplicationRecord
  has_many :character_spells, dependent: :destroy
  has_many :characters, through: :character_spells

  serialize :class_restriction, coder: JSON

  validates :name, :school, presence: true
  validates :name, uniqueness: true
  validates :tier, numericality: { only_integer: true, greater_than_or_equal_to: -1 }, allow_nil: true

  def available_to?(character)
    return false if character.character_class.blank?
    return false if character.story_subclass_restricted_spell_names.include?(name)
    return false if class_restricted_from?(character)
    return false if utility? && !character.utility_spell_names.include?(name)
    return true if character.story_granted_spell_names.include?(name)
    return false unless utility? || character.known_spell_schools.include?(school)

    tier.to_i <= character.character_class.spell_tier_for(character.level)
  end

  def utility?
    tier.to_i == -1
  end

  def citation
    { source_ref: source_ref.presence || "Core Rules 2.0.1, Spells", quote: source_quote.presence || description.presence }
  end

  private
    def class_restricted_from?(character)
      restrictions = Array(class_restriction).compact
      restrictions.any? && !restrictions.include?(character.character_class.name)
    end
end
