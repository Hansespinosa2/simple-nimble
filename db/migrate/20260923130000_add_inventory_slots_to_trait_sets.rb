class AddInventorySlotsToTraitSets < ActiveRecord::Migration[8.1]
  def change
    add_column :trait_sets, :inventory_slots, :integer
  end
end
