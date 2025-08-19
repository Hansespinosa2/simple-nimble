class Stat < ApplicationRecord
  belongs_to :character

  validates :name, inclusion: { in: ->(stat) { possible_stats } }
  validates :name, uniqueness: { scope: :character_id, message: "Character stat can only be changed, not duplicated." }

  def self.possible_stats
    [ "Strength", "Dexterity", "Intelligence", "Will" ]
  end
end
