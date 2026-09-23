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
end
