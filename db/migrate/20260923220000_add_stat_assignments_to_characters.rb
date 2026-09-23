class AddStatAssignmentsToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :stat_assignments, :text
  end
end
