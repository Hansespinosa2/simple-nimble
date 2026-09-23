class AddLevelUpRuleChoices < ActiveRecord::Migration[8.1]
  def change
    change_table :level_ups do |t|
      t.string :second_stat_name
      t.string :skill_from
      t.integer :hit_die_roll_one
      t.integer :hit_die_roll_two
    end
  end
end
