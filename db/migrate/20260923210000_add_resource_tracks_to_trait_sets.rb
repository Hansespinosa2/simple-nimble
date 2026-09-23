class AddResourceTracksToTraitSets < ActiveRecord::Migration[8.1]
  def change
    add_column :trait_sets, :resource_tracks, :text
  end
end
