class AddAncestryLanguageGrants < ActiveRecord::Migration[8.1]
  def change
    add_column :ancestries, :language_grants, :text
  end
end
