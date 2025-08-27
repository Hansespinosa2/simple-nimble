class Character < ApplicationRecord
  has_many :stats, dependent: :destroy
  accepts_nested_attributes_for :stats

  has_many :skills, dependent: :destroy
  accepts_nested_attributes_for :skills

  has_one :trait_set, dependent: :destroy
  accepts_nested_attributes_for :trait_set

  before_create :ensure_defaults



  def ensure_defaults
    build_default_stats if stats.empty?
    build_default_skills if skills.empty?
    build_default_trait_set if not trait_set
    Rails.logger.debug "Built trait set" if not trait_set
  end

  private
    def build_default_stats
      Stat.possible_stat_names.each do |stat_name|
        stats.build(name: stat_name, value: 0)
      end
    end

    def build_default_skills
      Skill.possible_skill_names.each do |skill_name|
        skills.build(name: skill_name, value: 0)
      end
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
