class AddBackgroundRuleModifiers < ActiveRecord::Migration[8.1]
  def change
    change_table :backgrounds do |t|
      t.integer :initiative_modifier, default: 0, null: false
      t.integer :armor_modifier, default: 0, null: false
      t.integer :max_hit_dice_modifier, default: 0, null: false
      t.integer :max_wounds_modifier, default: 0, null: false
      t.text :skill_modifiers
      t.text :language_grants
    end
  end
end
