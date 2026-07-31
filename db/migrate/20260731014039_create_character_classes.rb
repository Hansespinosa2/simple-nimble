class CreateCharacterClasses < ActiveRecord::Migration[8.1]
  def change
    create_table :character_classes do |t|
      t.string :name
      t.string :key_stat_one
      t.string :key_stat_two
      t.string :hit_die
      t.integer :starting_hp
      t.string :save_bonus_stat
      t.string :save_penalty_stat

      t.timestamps
    end
  end
end
