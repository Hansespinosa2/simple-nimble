class CreateAncestries < ActiveRecord::Migration[8.1]
  def change
    create_table :ancestries do |t|
      t.string :name
      t.string :size
      t.text :trait_summary

      t.timestamps
    end
  end
end
