class CreateSkillSets < ActiveRecord::Migration[8.0]
  def change
    create_table :skill_sets do |t|
      t.references :character, null: false, foreign_key: true
      t.integer :arcana
      t.integer :insight
      t.integer :examination
      t.integer :finesse
      t.integer :might
      t.integer :lore
      t.integer :influence
      t.integer :naturecraft
      t.integer :stealth
      t.integer :perception

      t.timestamps
    end
  end
end
