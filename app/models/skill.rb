class Skill < ApplicationRecord
  belongs_to :character

  validates :name, inclusion: { in: ->(skill) { possible_skill_names } }
  validates :name, uniqueness: { scope: :character_id, message: "Character skill can only be updated, not created." }

  def self.possible_skill_names
    [ "Arcana", "Insight", "Examination", "Finesse", "Might", "Lore", "Influence", "Naturecraft", "Stealth", "Perception" ]
  end
end
