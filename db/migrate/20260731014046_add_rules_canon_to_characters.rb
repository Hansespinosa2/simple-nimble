class AddRulesCanonToCharacters < ActiveRecord::Migration[8.1]
  def change
    # Nullable: existing characters predate rules-canon references. New
    # creation-flow characters are required (via model validation) to set
    # these; legacy rows are left as-is rather than backfilled with guesses.
    add_reference :characters, :character_class, null: true, foreign_key: true
    add_reference :characters, :ancestry, null: true, foreign_key: true
    add_reference :characters, :background, null: true, foreign_key: true
    add_column :characters, :stat_array, :string
  end
end
