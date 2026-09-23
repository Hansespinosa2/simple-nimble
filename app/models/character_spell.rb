class CharacterSpell < ApplicationRecord
  belongs_to :character
  belongs_to :spell

  validates :spell_id, uniqueness: { scope: :character_id }
end
