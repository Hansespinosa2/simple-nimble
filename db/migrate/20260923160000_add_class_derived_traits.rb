class AddClassDerivedTraits < ActiveRecord::Migration[8.1]
  def change
    change_table :characters do |t|
      t.text :starting_equipment
    end

    change_table :trait_sets do |t|
      t.integer :save_dc
      t.integer :max_mana
      t.integer :current_mana
      t.string :resource_name
      t.string :resource_formula
      t.string :resource_die
      t.integer :max_resource
      t.integer :current_resource
    end
  end
end
