class CreateLevelUps < ActiveRecord::Migration[8.1]
  def change
    create_table :level_ups do |t|
      t.references :character, null: false, foreign_key: true
      t.integer :from_level, null: false
      t.integer :to_level, null: false
      t.string :status, null: false, default: "draft"
      t.string :skill_name
      t.string :stat_name
      t.text :notes
      t.text :preview
      t.datetime :finalized_at

      t.timestamps
    end

    add_index :level_ups, [ :character_id, :status ]
  end
end
