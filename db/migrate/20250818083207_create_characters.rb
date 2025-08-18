class CreateCharacters < ActiveRecord::Migration[8.0]
  def change
    create_table :characters do |t|
      t.string :name
      t.string :race
      t.string :nimble_class
      t.integer :level
      t.string :background
      t.text :description
      t.string :languages

      t.timestamps
    end
  end
end
