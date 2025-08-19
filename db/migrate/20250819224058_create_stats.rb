class CreateStats < ActiveRecord::Migration[8.0]
  def change
    create_table :stats do |t|
      t.string :name
      t.integer :value
      t.references :character, null: false, foreign_key: true

      t.timestamps
    end
  end
end
