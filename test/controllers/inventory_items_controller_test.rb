require "test_helper"

# S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
class InventoryItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Mage")
    @character = Character.create!(
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
    assert_equal [ { "name" => "2 potions", "slots" => 1 } ], @character.character_revisions.order(:id).last.snapshot.fetch("inventory_items")
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
    assert_equal "Grouped camping supplies", @character.character_revisions.order(:id).last.snapshot.fetch("inventory_items").first.fetch("name")

    assert_difference("InventoryItem.count", -1) do
      assert_difference("CharacterRevision.count", 1) do
        delete character_inventory_item_url(@character, item)
      end
    end
    assert_not InventoryItem.exists?(item.id)
    assert_empty @character.reload.snapshot_payload.fetch("inventory_items")
    assert_equal 4, @character.inventory_slots_used
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
    @character.update!(account: Account.create!(display_name: "Owner", email: "inventory-owner@example.com"))

    assert_no_difference("InventoryItem.count") do
      post character_inventory_items_url(@character), params: {
        inventory_item: { name: "Unauthorized item", slots: 1 }
      }
    end

    assert_redirected_to character_url(@character)
    assert_equal "Only the player who owns this character can edit it.", flash[:alert]
  end
end
