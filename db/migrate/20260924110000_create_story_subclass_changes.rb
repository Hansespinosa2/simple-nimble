class CreateStorySubclassChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :story_subclass_changes do |t|
      t.references :character, null: false, foreign_key: true
      t.references :campaign, null: false, foreign_key: true
      t.references :approved_by_account, null: false, foreign_key: { to_table: :accounts }
      t.references :character_revision, null: false, foreign_key: true
      t.string :from_subclass, null: false
      t.string :to_subclass, null: false
      t.text :story_note, null: false
      t.string :source_ref, null: false

      t.timestamps
    end

    add_index :story_subclass_changes, [ :character_id, :created_at ], name: "index_story_subclass_changes_on_character_and_created_at"
  end
end
