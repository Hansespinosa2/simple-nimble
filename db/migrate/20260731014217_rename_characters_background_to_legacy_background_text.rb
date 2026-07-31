class RenameCharactersBackgroundToLegacyBackgroundText < ActiveRecord::Migration[8.1]
  def change
    # Frees up `background` for the new belongs_to :background rules-canon
    # association added in AddRulesCanonToCharacters; the old free-text
    # field is kept (not dropped) so existing character data isn't lost.
    rename_column :characters, :background, :legacy_background_text
  end
end
