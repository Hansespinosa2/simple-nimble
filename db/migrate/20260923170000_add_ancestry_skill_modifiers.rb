class AddAncestrySkillModifiers < ActiveRecord::Migration[8.1]
  def change
    add_column :ancestries, :skill_modifiers, :text
  end
end
