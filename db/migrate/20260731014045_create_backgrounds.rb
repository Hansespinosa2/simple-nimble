class CreateBackgrounds < ActiveRecord::Migration[8.1]
  def change
    create_table :backgrounds do |t|
      t.string :name
      t.text :description
      t.string :prerequisite_stat
      t.integer :prerequisite_max

      t.timestamps
    end
  end
end
