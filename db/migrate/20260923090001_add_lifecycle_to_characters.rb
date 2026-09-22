class AddLifecycleToCharacters < ActiveRecord::Migration[8.1]
  def change
    change_table :characters do |t|
      t.string :status, null: false, default: "draft"
      t.references :ruleset_version, foreign_key: true
      t.text :conditions
      t.text :inventory
      t.text :game_notes
    end

    add_index :characters, :status
  end
end
