class Character < ApplicationRecord
  validates :name, :race, :level, presence: true
end
