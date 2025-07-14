class Character < ApplicationRecord
  validates :name, :race, :level, presence: true
  validates :level, comparison: {greater_than_or_equal_to: 0}
end
