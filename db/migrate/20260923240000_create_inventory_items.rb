class CreateInventoryItems < ActiveRecord::Migration[8.1]
  def change
    create_table :inventory_items do |t|
      t.references :character, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :slots, null: false, default: 1

      t.timestamps
    end
  end
end
