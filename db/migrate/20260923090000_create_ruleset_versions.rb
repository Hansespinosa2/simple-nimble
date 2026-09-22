class CreateRulesetVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :ruleset_versions do |t|
      t.string :name, null: false
      t.string :version, null: false
      t.string :source_reference
      t.boolean :active, null: false, default: true
      t.datetime :published_at

      t.timestamps
    end

    add_index :ruleset_versions, [ :name, :version ], unique: true
  end
end
