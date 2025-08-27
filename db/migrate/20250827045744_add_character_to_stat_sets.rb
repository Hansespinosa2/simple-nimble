class AddCharacterToStatSets < ActiveRecord::Migration[8.0]
  def change
    add_reference :stat_sets, :character, null: false, foreign_key: true
  end
end
