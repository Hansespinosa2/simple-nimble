class AddSpellRulesMetadata < ActiveRecord::Migration[8.1]
  def change
    change_table :characters do |t|
      t.string :spell_school_choice
    end

    change_table :spells do |t|
      t.integer :mana_cost
      t.string :target_type
      t.string :range_or_reach
      t.string :condition_applied
      t.text :class_restriction
      t.string :source_ref
      t.text :source_quote
    end
  end
end
