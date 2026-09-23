class DeduplicateSpellsAndCharacterSpells < ActiveRecord::Migration[8.1]
  def up
    duplicate_names = select_values("SELECT name FROM spells WHERE name IS NOT NULL GROUP BY name HAVING COUNT(*) > 1")

    duplicate_names.each do |name|
      spell_ids = select_values("SELECT id FROM spells WHERE name = #{connection.quote(name)} ORDER BY id").map(&:to_i)
      canonical_id = spell_ids.shift

      spell_ids.each do |duplicate_id|
        execute "UPDATE character_spells SET spell_id = #{canonical_id} WHERE spell_id = #{duplicate_id}"
        execute "DELETE FROM spells WHERE id = #{duplicate_id}"
      end
    end

    execute <<~SQL
      DELETE FROM character_spells
      WHERE id NOT IN (
        SELECT MIN(id) FROM character_spells GROUP BY character_id, spell_id
      )
    SQL

    add_index :spells, :name, unique: true, name: "index_spells_on_name_unique"
    add_index :character_spells, [ :character_id, :spell_id ], unique: true, name: "index_character_spells_on_character_and_spell"
  end

  def down
    remove_index :character_spells, name: "index_character_spells_on_character_and_spell"
    remove_index :spells, name: "index_spells_on_name_unique"
  end
end
