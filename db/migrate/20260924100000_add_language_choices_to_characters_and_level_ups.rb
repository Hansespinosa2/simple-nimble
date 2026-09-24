class AddLanguageChoicesToCharactersAndLevelUps < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :language_choices, :text, default: "[]", null: false
    add_column :characters, :feature_language_choices, :text, default: "{}", null: false
    add_column :level_ups, :language_choices, :text, default: "[]", null: false
    add_column :level_ups, :feature_language_choices, :text, default: "{}", null: false
  end
end
