class CharacterRevision < ApplicationRecord
  belongs_to :character

  serialize :snapshot, coder: JSON

  validates :event_type, :snapshot, presence: true

  EVENT_LABELS = {
    "created" => "Created",
    "finalized" => "Finalized as playable",
    "level_up" => "Leveled up",
    "safe_rest" => "Safe Rest",
    "field_rest" => "Field Rest",
    "inventory_update" => "Inventory update",
    "game_update" => "Game update",
    "edited" => "Edited"
  }.freeze

  def event_label
    EVENT_LABELS.fetch(event_type, event_type.humanize)
  end
end
