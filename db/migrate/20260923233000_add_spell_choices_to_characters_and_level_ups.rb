class AddSpellChoicesToCharactersAndLevelUps < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :spell_choices, :text
    add_column :level_ups, :spell_choices, :text
  end
end
