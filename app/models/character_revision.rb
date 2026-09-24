class CharacterRevision < ApplicationRecord
  belongs_to :character
  has_one :story_subclass_change, dependent: :restrict_with_error

  serialize :snapshot, coder: JSON

  validates :event_type, :snapshot, presence: true

  EVENT_LABELS = {
    "created" => "Created",
    "finalized" => "Finalized as playable",
    "level_up" => "Leveled up",
    "initiative_roll" => "Initiative rolled",
    "weapon_summoned" => "Bonescythe summoned",
    "weapon_shattered" => "Bonescythe shattered",
    "shadow_minion_update" => "Shadow Minion update",
    "shadow_exploit" => "Shadow Exploit",
    "my_blood_my_power" => "My Blood, My Power",
    "encounter_end" => "Encounter ended",
    "safe_rest" => "Safe Rest",
    "field_rest" => "Field Rest",
    "inventory_update" => "Inventory update",
    "game_update" => "Game update",
    "story_subclass_change" => "GM-approved story subclass change",
    "edited" => "Edited"
  }.freeze

  def event_label
    EVENT_LABELS.fetch(event_type, event_type.humanize)
  end
end
