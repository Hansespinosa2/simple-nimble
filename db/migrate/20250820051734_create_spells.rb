class CreateSpells < ActiveRecord::Migration[8.0]
  def change
    create_table :spells do |t|
      t.string :school
      t.string :name
      t.integer :tier
      t.integer :target
      t.integer :action_cost
      t.integer :range
      t.string :damage
      t.text :description
      t.integer :casting_time
      t.text :high_level
      t.text :upcast

      t.timestamps
    end
  end
end
