class AddBonescytheStateToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :bonescythe_summoned, :boolean, null: false, default: false
  end
end
