class InventoryItem < ApplicationRecord
  belongs_to :character

  before_validation :normalize_name
  before_validation :clear_starting_gear_source_if_renamed

  validates :name, presence: true, length: { maximum: 120 }
  validates :slots, numericality: { only_integer: true, greater_than: 0 }
  validates :source_ref, presence: true, if: :starting_gear?
  validates :catalog_slots, numericality: { only_integer: true, greater_than: 0 }, if: :starting_gear?

  private
    def normalize_name
      self.name = name.to_s.strip
    end

    def clear_starting_gear_source_if_renamed
      return unless persisted? && starting_gear? && will_save_change_to_name?

      self.starting_gear = false
      self.source_ref = nil
      self.catalog_slots = nil
    end
end
