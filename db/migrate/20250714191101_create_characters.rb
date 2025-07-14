class CreateCharacters < ActiveRecord::Migration[8.0]
  def change
    create_table :characters do |t|
      t.string :name
      t.string :race
      t.integer :level
      t.text :background
      t.text :description
      t.string :languages
      t.string :proficiencies

      t.timestamps
    end
  end
end
