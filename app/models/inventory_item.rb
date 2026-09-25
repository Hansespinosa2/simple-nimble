class InventoryItem < ApplicationRecord
  belongs_to :character

  before_validation :normalize_name
  before_validation :clear_starting_gear_source_if_renamed
  before_validation :sync_catalog_armor_metadata
  after_save :unequip_conflicting_armor_items, if: :equipped?
  after_save :recalculate_character_equipment_derived_values
  after_destroy :recalculate_character_equipment_derived_values

  validates :name, presence: true, length: { maximum: 120 }
  validates :slots, numericality: { only_integer: true, greater_than: 0 }
  validates :source_ref, presence: true, if: :starting_gear?
  validates :catalog_slots, numericality: { only_integer: true, greater_than: 0 }, if: :catalog_slot_source_required?
  validate :equipped_armor_meets_strength_requirement, if: :equipped?

  def armor_profile
    Rules::NimbleCatalog.equipment_armor_item(name)
  end

  private
    def normalize_name
      self.name = name.to_s.strip
    end

    def clear_starting_gear_source_if_renamed
      return unless persisted? && will_save_change_to_name?

      self.starting_gear = false if starting_gear?
      self.source_ref = nil
      self.catalog_slots = nil
      self.equipped = false unless Rules::NimbleCatalog.equipment_armor_item(name)
    end

    def sync_catalog_armor_metadata
      rules = armor_profile
      return unless rules

      self.source_ref ||= rules.fetch("source_ref")
      target_slots = equipped? ? rules.fetch("slots_worn").to_i : rules.fetch("slots_unworn").to_i

      if new_record? || will_save_change_to_name?
        self.slots = target_slots
        self.catalog_slots = target_slots
      elsif will_save_change_to_equipped?
        previous_slots = attribute_in_database("slots").to_i
        previous_catalog_slots = attribute_in_database("catalog_slots").to_i
        custom_slot_count = previous_slots != previous_catalog_slots || (will_save_change_to_slots? && slots.to_i != previous_catalog_slots)
        self.slots = target_slots unless custom_slot_count
        self.catalog_slots = target_slots
      elsif catalog_slots.blank?
        self.slots = target_slots unless will_save_change_to_slots?
        self.catalog_slots = target_slots
      end
    end

    def unequip_conflicting_armor_items
      rules = armor_profile
      return unless rules

      character.inventory_items.where(equipped: true).where.not(id: id).find_each do |other_item|
        other_rules = other_item.armor_profile
        next unless other_rules && other_rules.fetch("kind") == rules.fetch("kind")

        other_item.update!(equipped: false)
      end
    end

    def recalculate_character_equipment_derived_values
      character.recalculate_equipment_derived_values!
    end

    def catalog_slot_source_required?
      starting_gear? || armor_profile.present?
    end

    def equipped_armor_meets_strength_requirement
      rules = armor_profile
      return if rules.blank? || character.equipment_armor_requirement_met?(rules)

      errors.add(:equipped, "requires at least STR #{rules.fetch('strength_requirement')}")
    end
end
