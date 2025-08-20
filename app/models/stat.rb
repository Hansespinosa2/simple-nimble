class Stat < ApplicationRecord
  belongs_to :character

  validates :name, inclusion: { in: ->(stat) { possible_stats } }
  validates :name, uniqueness: { scope: :character_id, message: "Character stat can only be changed, not duplicated." }

  def shorthand
    self.name.first(3).upcase
  end


  def self.possible_stats
    [ "Strength", "Dexterity", "Intelligence", "Will" ]
  end
end
