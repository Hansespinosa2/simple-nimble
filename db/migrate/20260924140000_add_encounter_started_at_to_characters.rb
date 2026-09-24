class AddEncounterStartedAtToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :encounter_started_at, :datetime
  end
end
