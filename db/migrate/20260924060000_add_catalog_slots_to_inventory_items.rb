class AddCatalogSlotsToInventoryItems < ActiveRecord::Migration[8.1]
  def up
    add_column :inventory_items, :catalog_slots, :integer
    execute "UPDATE inventory_items SET catalog_slots = slots WHERE starting_gear = TRUE"
  end

  def down
    remove_column :inventory_items, :catalog_slots
  end
end
