class Skill < ApplicationRecord
  belongs_to :character

  validates :name, inclusion: { in: ->(skill) { possible_skills } }
  validates :name, uniqueness: { scope: :character_id, message: "Character skill can only be updated, not created." }

  def self.possible_skills
    [ "Arcana", "Insight", "Examination", "Finesse", "Might", "Lore", "Influence", "Naturecraft", "Stealth", "Perception" ]
  end
end
