require "yaml"

class AddEquippedStateToInventoryItems < ActiveRecord::Migration[8.1]
  class InventoryItemRecord < ActiveRecord::Base
    self.table_name = "inventory_items"
  end

  def up
    add_column :inventory_items, :equipped, :boolean, null: false, default: false

    backfill_starting_armor
  end

  def backfill_starting_armor
    armor_items = YAML.safe_load_file(Rails.root.join("config/rules/nimble_v2_0_1.yml"))
      .fetch("equipment_armor").fetch("items")

    InventoryItemRecord.where(starting_gear: true).find_each do |item|
      armor = armor_items[item.name]
      next unless armor

      catalog_slots = armor.fetch("slots_worn").to_i
      custom_slot_count = item.catalog_slots.present? && item.slots != item.catalog_slots
      item.update_columns(
        equipped: true,
        slots: custom_slot_count ? item.slots : catalog_slots,
        catalog_slots: catalog_slots
      )
    end
  end

  def down
    remove_column :inventory_items, :equipped
  end
end
