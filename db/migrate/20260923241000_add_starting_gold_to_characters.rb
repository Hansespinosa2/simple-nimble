class AddStartingGoldToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :starting_equipment_choice, :string, null: false, default: "class_gear"
    add_column :characters, :current_gold, :integer, null: false, default: 0
  end
end
