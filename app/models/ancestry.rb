class Ancestry < ApplicationRecord
  # Structured rules-canon record (spec 02): the seed catalog enumerates the
  # published ancestries and stores the flat modifiers this sheet can derive.
  # Flat numeric modifiers:
  # speed_modifier, initiative_modifier, all_skills_bonus,
  # max_hit_dice_modifier, max_wounds_modifier, and armor_modifier.
  # Most Nimble ancestries' real effects are situational or triggered rather
  # than flat math, so those ancestries intentionally keep all 6 columns at 0
  # and describe their actual effect only in trait_summary.
  has_many :characters, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :size, presence: true
end
