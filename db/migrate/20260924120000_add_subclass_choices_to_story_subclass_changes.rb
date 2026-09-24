class AddSubclassChoicesToStorySubclassChanges < ActiveRecord::Migration[8.1]
  def change
    add_column :story_subclass_changes, :subclass_choices, :text, null: false, default: "{}"
  end
end
