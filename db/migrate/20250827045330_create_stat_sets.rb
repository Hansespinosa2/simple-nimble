class CreateStatSets < ActiveRecord::Migration[8.0]
  def change
    create_table :stat_sets do |t|
      t.integer :strength
      t.integer :dexterity
      t.integer :intelligence
      t.integer :will

      t.timestamps
    end
  end
end
