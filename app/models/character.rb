class Character < ApplicationRecord
  has_many :stats, dependent: :destroy
  has_many :skills, dependent: :destroy

  after_create :init_default_stats

  private
  def init_default_stats
    Stat.possible_stats.each do |stat_name|
      stats.create(name: stat_name, value: 0)
    end
  end
end
