class Character < ApplicationRecord
  has_many :stats, dependent: :destroy
  accepts_nested_attributes_for :stats

  has_many :skills, dependent: :destroy
  accepts_nested_attributes_for :skills

  has_many :trait_sets, dependent: :destroy
  accepts_nested_attributes_for :trait_sets

  after_create :init_default_stats, :init_default_skills

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
end
