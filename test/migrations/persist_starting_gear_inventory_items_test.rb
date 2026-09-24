require "test_helper"
require Rails.root.join("db/migrate/20260924050000_persist_starting_gear_inventory_items").to_s

# S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
class PersistStartingGearInventoryItemsTest < ActiveSupport::TestCase
  test "backfills source-backed class kits once for existing characters" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    character = Character.create!(name: "Legacy Inventory Mage", character_class: CharacterClass.find_by!(name: "Mage"))
    character.inventory_items.where(starting_gear: true).delete_all

    migration = PersistStartingGearInventoryItems.new
    migration.send(:backfill_class_starting_gear)
    migration.send(:backfill_class_starting_gear)
    items = character.starting_gear_inventory_items.order(:id).to_a

    assert_equal [ "Adventurer's Garb", "Staff", "Soap" ], items.map(&:name)
    assert_equal [ 1, 2, 1 ], items.map(&:slots)
    assert_equal [ 1, 2, 1 ], items.map(&:catalog_slots)
    assert items.all? { |item| item.source_ref.present? }
    assert_equal 4, character.inventory_slots_used
  end
end
