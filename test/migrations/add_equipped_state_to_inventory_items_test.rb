require "test_helper"
require Rails.root.join("db/migrate/20260924093000_add_equipped_state_to_inventory_items").to_s

# S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
class AddEquippedStateToInventoryItemsTest < ActiveSupport::TestCase
  test "backfills only catalog armor from existing starting kits and remains idempotent" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Oathsworn")
    character = Character.create!(name: "Legacy Armor Kit", character_class: CharacterClass.find_by!(name: "Oathsworn"))
    armor = character.starting_gear_inventory_items.find_by!(name: "Rusty Mail")
    shield = character.starting_gear_inventory_items.find_by!(name: "Wooden Buckler")
    weapon = character.starting_gear_inventory_items.find_by!(name: "Mace")

    armor.update_columns(equipped: false, slots: 3, catalog_slots: 1)
    shield.update_columns(equipped: false, slots: 1, catalog_slots: 1)
    weapon.update_columns(equipped: false, slots: 2, catalog_slots: 2)

    migration = AddEquippedStateToInventoryItems.new
    2.times { migration.send(:backfill_starting_armor) }

    assert_predicate armor.reload, :equipped?
    assert_equal [ 3, 1 ], [ armor.slots, armor.catalog_slots ], "the migration preserves a table-adjusted slot count"
    assert_predicate shield.reload, :equipped?
    assert_equal [ 1, 1 ], [ shield.slots, shield.catalog_slots ]
    assert_not weapon.reload.equipped?
    assert_equal [ 2, 2 ], [ weapon.slots, weapon.catalog_slots ]
  end
end
