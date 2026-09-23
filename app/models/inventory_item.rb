class InventoryItem < ApplicationRecord
  belongs_to :character

  before_validation :normalize_name

  validates :name, presence: true, length: { maximum: 120 }
  validates :slots, numericality: { only_integer: true, greater_than: 0 }

  private
    def normalize_name
      self.name = name.to_s.strip
    end
end
