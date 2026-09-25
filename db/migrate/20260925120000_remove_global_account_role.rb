class RemoveGlobalAccountRole < ActiveRecord::Migration[8.1]
  def change
    remove_column :accounts, :role, :string, default: "player", null: false
  end
end
