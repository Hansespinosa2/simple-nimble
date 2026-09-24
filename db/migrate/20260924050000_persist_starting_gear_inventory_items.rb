require "yaml"

class PersistStartingGearInventoryItems < ActiveRecord::Migration[8.1]
  class CharacterRecord < ActiveRecord::Base
    self.table_name = "characters"
  end

  class CharacterClassRecord < ActiveRecord::Base
    self.table_name = "character_classes"
  end

  class InventoryItemRecord < ActiveRecord::Base
    self.table_name = "inventory_items"
  end

  def up
    add_column :inventory_items, :starting_gear, :boolean, null: false, default: false
    add_column :inventory_items, :source_ref, :string
    add_index :inventory_items, [ :character_id, :starting_gear ]

    backfill_class_starting_gear
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Starting kit rows are editable game state and cannot be safely reconstructed after rollback."
  end

  private
    def backfill_class_starting_gear
      catalog = YAML.safe_load_file(Rails.root.join("config/rules/nimble_v2_0_1.yml"))
      classes = catalog.fetch("classes")
      item_rules = catalog.fetch("starting_gear_inventory").fetch("items")

      CharacterRecord.where(starting_equipment_choice: "class_gear").where.not(character_class_id: nil).find_each do |character|
        next if InventoryItemRecord.exists?(character_id: character.id, starting_gear: true)

        class_name = CharacterClassRecord.where(id: character.character_class_id).pick(:name)
        class_gear = classes.dig(class_name, "starting_gear")
        next if class_gear.blank?

        class_gear.each do |item_name|
          item_rule = item_rules.fetch(item_name)
          attributes = {
            character_id: character.id,
            name: item_name,
            slots: item_rule.fetch("slots"),
            starting_gear: true,
            source_ref: item_rule.fetch("source_ref")
          }
          attributes[:catalog_slots] = item_rule.fetch("slots") if column_exists?(:inventory_items, :catalog_slots)
          InventoryItemRecord.create!(attributes)
        end
      end
    end
end
