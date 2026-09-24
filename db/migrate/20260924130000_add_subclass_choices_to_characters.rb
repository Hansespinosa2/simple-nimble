class AddSubclassChoicesToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :subclass_choices, :text, null: false, default: "{}"
  end
end
