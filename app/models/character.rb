class Character < ApplicationRecord
  has_one :stat_set, dependent: :destroy
  has_one :skill_set, dependent: :destroy
  has_one :trait_set, dependent: :destroy

  accepts_nested_attributes_for :stat_set
  accepts_nested_attributes_for :skill_set
  accepts_nested_attributes_for :trait_set

  before_create :ensure_defaults

  def ensure_defaults
    build_default_stat_set if not stat_set
    build_default_skill_set if not skill_set
    build_default_trait_set if not trait_set
  end

  private
    def build_default_stat_set
      build_stat_set  strength: 0,
                      dexterity: 0,
                      intelligence: 0,
                      will: 0
    end

    def build_default_skill_set
      build_skill_set arcana: 0,
                      insight: 0,
                      examination: 0,
                      finesse: 0,
                      might: 0,
                      lore: 0,
                      influence: 0,
                      naturecraft: 0,
                      stealth: 0,
                      perception: 0
    end

    def build_default_trait_set
      build_trait_set initiative:        0,
                      speed:             30,
                      hit_die:           "1d6",
                      current_hit_dice:  1,
                      max_hit_dice:      1,
                      current_actions:   3,
                      max_actions:       3,
                      armor:             0,
                      temp_hp:           0,
                      current_hp:        10,
                      max_hp:            10,
                      current_wounds:    6,
                      max_wounds:        6
    end
end
