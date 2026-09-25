require "test_helper"

# S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
class InventoryItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    @account = create_account(display_name: "Inventory Player", email: "inventory-#{SecureRandom.hex(4)}@example.com")
    sign_in(@account)
    @character = Character.create!(
      account: @account,
      name: "Inventory Test Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
  end

  test "adding gear records its slot use in the sheet and revision snapshot" do
    assert_difference("InventoryItem.count") do
      assert_difference("CharacterRevision.count") do
        post character_inventory_items_url(@character), params: {
          inventory_item: { name: "2 potions", slots: 1 }
        }
      end
    end

    item = @character.inventory_items.order(:id).last
    assert_redirected_to character_url(@character)
    assert_equal "2 potions", item.name
    assert_equal 1, item.slots
    assert_equal 5, @character.reload.inventory_slots_used
    snapshot_items = @character.character_revisions.order(:id).last.snapshot.fetch("inventory_items")
    assert_equal 4, snapshot_items.size
    assert_equal "2 potions", snapshot_items.last.fetch("name")
    assert_equal false, snapshot_items.last.fetch("starting_gear")
    assert_equal 3, snapshot_items.count { |snapshot_item| snapshot_item.fetch("starting_gear") }
    assert snapshot_items.select { |snapshot_item| snapshot_item.fetch("starting_gear") }.all? { |snapshot_item| snapshot_item.fetch("source_ref").present? }
  end

  test "inventory can exceed capacity without blocking the GM-waivable rules option" do
    item_slots = @character.inventory_slots_capacity - @character.starting_gear_inventory_slots + 1

    post character_inventory_items_url(@character), params: {
      inventory_item: { name: "Oversized treasure", slots: item_slots }
    }

    assert_redirected_to character_url(@character)
    assert_equal @character.inventory_slots_capacity + 1, @character.reload.inventory_slots_used
    assert_includes @character.reload.snapshot_payload.fetch("inventory_items").map { |item| item.fetch("name") }, "Oversized treasure"
  end

  test "updating and removing a carried item each create auditable revisions" do
    item = @character.inventory_items.create!(name: "Travel rations", slots: 1)

    assert_difference("CharacterRevision.count", 1) do
      patch character_inventory_item_url(@character, item), params: {
        inventory_item: { name: "Grouped camping supplies", slots: 2 }
      }
    end
    assert_equal "Grouped camping supplies", item.reload.name
    assert_equal 2, item.slots
    assert_equal 6, @character.reload.inventory_slots_used
    snapshot_items = @character.character_revisions.order(:id).last.snapshot.fetch("inventory_items")
    assert_equal "Grouped camping supplies", snapshot_items.find { |snapshot_item| snapshot_item.fetch("name") == "Grouped camping supplies" }.fetch("name")

    assert_difference("InventoryItem.count", -1) do
      assert_difference("CharacterRevision.count", 1) do
        delete character_inventory_item_url(@character, item)
      end
    end
    assert_not InventoryItem.exists?(item.id)
    assert_not_includes @character.reload.snapshot_payload.fetch("inventory_items").map { |snapshot_item| snapshot_item.fetch("name") }, "Grouped camping supplies"
    assert_equal 4, @character.inventory_slots_used
  end

  test "removing a starting kit item updates the game load and its revision" do
    staff = @character.starting_gear_inventory_items.find_by!(name: "Staff")

    assert_difference("InventoryItem.count", -1) do
      assert_difference("CharacterRevision.count", 1) do
        delete character_inventory_item_url(@character, staff)
      end
    end

    assert_not InventoryItem.exists?(staff.id)
    assert_equal 2, @character.reload.inventory_slots_used
    assert_equal 2, @character.starting_gear_inventory_slots
    snapshot_items = @character.character_revisions.order(:id).last.snapshot.fetch("inventory_items")
    assert_not_includes snapshot_items.map { |snapshot_item| snapshot_item.fetch("name") }, "Staff"
    assert_equal 2, snapshot_items.count { |snapshot_item| snapshot_item.fetch("starting_gear") }
  end

  test "renaming a starting item clears its original gear source without dropping it" do
    staff = @character.starting_gear_inventory_items.find_by!(name: "Staff")

    patch character_inventory_item_url(@character, staff), params: {
      inventory_item: { name: "Enchanted Staff", slots: 2 }
    }

    assert_redirected_to character_url(@character)
    staff.reload
    assert_equal "Enchanted Staff", staff.name
    assert_not staff.starting_gear?
    assert_nil staff.source_ref
    assert_equal 4, @character.reload.inventory_slots_used
  end

  test "adjusting a starting item's slots preserves its class-kit source" do
    staff = @character.starting_gear_inventory_items.find_by!(name: "Staff")

    patch character_inventory_item_url(@character, staff), params: {
      inventory_item: { name: "Staff", slots: 3 }
    }

    assert_redirected_to character_url(@character)
    assert_equal 3, staff.reload.slots
    assert_predicate staff, :starting_gear?
    assert staff.source_ref.present?
    assert_equal 2, staff.catalog_slots
    assert_equal 5, @character.reload.inventory_slots_used
    snapshot_item = @character.character_revisions.order(:id).last.snapshot.fetch("inventory_items").find { |item| item.fetch("name") == "Staff" }
    assert_equal 3, snapshot_item.fetch("slots")
    assert snapshot_item.fetch("starting_gear")
    assert snapshot_item.fetch("source_ref").present?
    assert_equal 2, snapshot_item.fetch("catalog_slots")

    get character_url(@character)
    assert_select ".inventory-item-source", text: /adjusted from 2 catalog slots/
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "equipping armor updates Armor, conflicts, slots, and revision history" do
    garb = @character.starting_gear_inventory_items.find_by!(name: "Adventurer's Garb")
    post character_inventory_items_url(@character), params: {
      inventory_item: { name: "Rusty Mail", slots: 1 }
    }
    plate = @character.inventory_items.find_by!(name: "Rusty Mail")

    assert_equal 2, plate.slots, "the catalog's unworn weight overrides an arbitrary create-form default"
    armor_before = @character.reload.trait_set.armor

    patch character_inventory_item_url(@character, plate), params: {
      inventory_item: { name: "Rusty Mail", slots: 2, equipped: "1" }
    }

    assert_redirected_to character_url(@character)
    assert_predicate plate.reload, :equipped?
    assert_equal 1, plate.slots
    assert_not garb.reload.equipped?
    assert_equal 5, @character.reload.trait_set.armor
    assert_not_equal armor_before, @character.trait_set.armor
    snapshot_item = @character.character_revisions.order(:id).last.snapshot.fetch("inventory_items").find { |item| item.fetch("name") == "Rusty Mail" }
    assert_equal true, snapshot_item.fetch("equipped")
    assert_equal 1, snapshot_item.fetch("catalog_slots")
  end

  test "an inventory item cannot be edited through another character's nested URL" do
    other_character = Character.create!(name: "Other Inventory Mage", character_class: @character.character_class)
    item = other_character.inventory_items.create!(name: "Private key", slots: 1)

    patch character_inventory_item_url(@character, item), params: {
      inventory_item: { name: "Stolen key", slots: 1 }
    }

    assert_response :not_found
    assert_equal "Private key", item.reload.name
  end

  test "only the character owner can change structured inventory" do
    @character.update!(account: create_account(display_name: "Owner", email: "inventory-owner@example.com"))

    assert_no_difference("InventoryItem.count") do
      post character_inventory_items_url(@character), params: {
        inventory_item: { name: "Unauthorized item", slots: 1 }
      }
    end

    assert_response :not_found
  end
end
