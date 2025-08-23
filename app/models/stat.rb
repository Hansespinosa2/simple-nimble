class Stat < ApplicationRecord
  belongs_to :character

  validates :name, inclusion: { in: ->(stat) { possible_stat_names } }
  validates :name, uniqueness: { scope: :character_id, message: "Character stat can only be changed, not duplicated." }

  def self.possible_stat_names
    [ "Strength", "Dexterity", "Intelligence", "Will" ]
  end
end
