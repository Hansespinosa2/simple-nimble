class AddFeatureChoicesToCharactersAndLevelUps < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :feature_choices, :text
    add_column :level_ups, :feature_choices, :text
  end
end
