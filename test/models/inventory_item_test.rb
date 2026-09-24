require "test_helper"

# S-02:AC-1 S-02:AC-2 S-09:AC-3
class InventoryItemTest < ActiveSupport::TestCase
  test "trims item names and rejects missing names or non-positive slot use" do
    item = InventoryItem.new(character: Character.new, name: "  Pair of potions  ", slots: 1)

    assert_predicate item, :valid?
    assert_equal "Pair of potions", item.name

    item.name = "  "
    item.slots = 0
    assert_not item.valid?
    assert_includes item.errors.attribute_names, :name
    assert_includes item.errors.attribute_names, :slots
  end

  test "starting gear requires a source and renaming detaches that source" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    character = Character.create!(name: "Source Test Mage", character_class: CharacterClass.find_by!(name: "Mage"))
    staff = character.starting_gear_inventory_items.find_by!(name: "Staff")
    assert_predicate staff, :valid?
    assert_predicate staff, :starting_gear?
    assert staff.source_ref.present?
    assert_equal 2, staff.catalog_slots

    unsourced_starting_item = InventoryItem.new(
      character: character,
      name: "Unknown kit item",
      slots: 1,
      catalog_slots: 1,
      starting_gear: true
    )
    assert_not unsourced_starting_item.valid?
    assert_includes unsourced_starting_item.errors.attribute_names, :source_ref

    staff.update!(name: "Enchanted Staff")

    assert_not staff.starting_gear?
    assert_nil staff.source_ref
    assert_nil staff.catalog_slots
    assert_equal 4, character.reload.inventory_slots_used
  end
end
