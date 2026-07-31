class AddMechanicalModifiersToAncestries < ActiveRecord::Migration[8.1]
  def change
    add_column :ancestries, :speed_modifier, :integer, default: 0, null: false
    add_column :ancestries, :initiative_modifier, :integer, default: 0, null: false
    add_column :ancestries, :all_skills_bonus, :integer, default: 0, null: false
    add_column :ancestries, :max_hit_dice_modifier, :integer, default: 0, null: false
    add_column :ancestries, :max_wounds_modifier, :integer, default: 0, null: false
    add_column :ancestries, :armor_modifier, :integer, default: 0, null: false
  end
end
