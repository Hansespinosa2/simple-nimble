class CreateTraitSets < ActiveRecord::Migration[8.0]
  def change
    create_table :trait_sets do |t|
      t.references :character, null: false, foreign_key: true
      t.integer :initiative
      t.integer :speed
      t.string :hit_die
      t.integer :current_hit_dice
      t.integer :max_hit_dice
      t.integer :current_actions
      t.integer :max_actions
      t.integer :armor
      t.integer :temp_hp
      t.integer :current_hp
      t.integer :max_hp
      t.integer :current_wounds
      t.integer :max_wounds

      t.timestamps
    end
  end
end
