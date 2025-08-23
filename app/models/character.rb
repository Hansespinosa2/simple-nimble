class Character < ApplicationRecord
  has_many :stats, dependent: :destroy
  accepts_nested_attributes_for :stats

  has_many :skills, dependent: :destroy
  accepts_nested_attributes_for :skills

  has_one :trait_set, dependent: :destroy
  accepts_nested_attributes_for :trait_set

  after_create :init_default_stats, :init_default_skills, :init_default_trait_set

  private
  def init_default_stats
    Stat.possible_stat_names.each do |stat_name|
      stats.create(name: stat_name, value: 0)
    end
  end

  def init_default_skills
    Skill.possible_skill_names.each do |skill_name|
      skills.create(name: skill_name, value: 0)
    end
  end

  def init_default_trait_set
    create_trait_set initiative:        0,
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
