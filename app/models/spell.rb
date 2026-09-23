class Spell < ApplicationRecord
  has_many :character_spells, dependent: :destroy
  has_many :characters, through: :character_spells

  validates :name, :school, presence: true
  validates :tier, numericality: { only_integer: true, greater_than_or_equal_to: -1 }, allow_nil: true
end
