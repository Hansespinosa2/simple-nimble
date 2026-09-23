class AddSubclassChoices < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :subclass_name, :string
    add_column :level_ups, :subclass_name, :string
  end
end
