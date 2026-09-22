class CreateCharacterRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :character_revisions do |t|
      t.references :character, null: false, foreign_key: true
      t.string :event_type, null: false
      t.integer :from_level
      t.integer :to_level
      t.string :summary
      t.text :snapshot, null: false

      t.timestamps
    end

    add_index :character_revisions, [ :character_id, :created_at ]
  end
end
