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

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "catalog armor uses worn and unworn slots and only one item of each kind can be equipped" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Oathsworn")
    character = Character.create!(
      name: "Armor Inventory Test",
      character_class: CharacterClass.find_by!(name: "Oathsworn"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    plate = character.inventory_items.create!(name: "Rusty Mail")
    second_armor = character.inventory_items.create!(name: "Cheap Hides")
    iron_shield = character.inventory_items.create!(name: "Iron Shield")

    assert_equal [ 2, 2, 1 ], [ plate.slots, second_armor.slots, iron_shield.slots ]
    assert_equal [ 2, 2, 1 ], [ plate.catalog_slots, second_armor.catalog_slots, iron_shield.catalog_slots ]
    assert_equal "Core Rules 2.0.1, p. 33", iron_shield.source_ref

    plate.update!(slots: 3)
    plate.update!(equipped: true)
    second_armor.update!(equipped: true)
    iron_shield.update!(equipped: true)

    assert_equal 3, plate.reload.slots, "a table-adjusted slot count remains stable when equipment state changes"
    assert_equal 2, plate.catalog_slots
    assert_not plate.equipped?, "equipping the second body armor replaces the first"
    assert_predicate second_armor.reload, :equipped?
    assert_equal 1, second_armor.slots
    assert_predicate iron_shield.reload, :equipped?, "a shield is a separate equipment kind"
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "renaming a catalog armor item to another catalog item resets its catalog slot baseline" do
    character = Character.create!(name: "Armor Rename Test")
    armor = character.inventory_items.create!(name: "Wooden Buckler", equipped: false)

    armor.update!(name: "Adventurer's Garb")

    assert_equal 2, armor.slots
    assert_equal 2, armor.catalog_slots
    assert_equal "Core Rules 2.0.1, p. 33", armor.source_ref
    assert_not armor.equipped?
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2
  test "an armor STR requirement blocks equipping until the character meets it" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    mage = Character.create!(
      name: "Understrength Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      stat_array: "balanced",
      starting_equipment_choice: "starting_gold"
    )
    plate = mage.inventory_items.create!(name: "Rusty Plate")

    assert_equal 1, mage.stat_value("strength")
    assert_not plate.update(equipped: true)
    assert_includes plate.errors[:equipped], "requires at least STR 2"
    assert_not plate.reload.equipped?
    assert_equal 2, plate.slots

    mage.stat_set.update!(strength: 2)
    assert plate.update(equipped: true)
    assert_predicate plate.reload, :equipped?
    assert_equal 1, plate.slots

    mage.stat_set.update!(strength: 1)
    assert_equal mage.stat_value("dexterity"), mage.armor_for, "an equipped item stops contributing if its STR requirement later becomes unmet"
  end
end
