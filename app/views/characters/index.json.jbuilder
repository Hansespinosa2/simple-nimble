json.array! @characters do |character|
  json.extract! character, :id, :name, :level, :status, :description, :updated_at
  json.status_label character.status_label
  json.rules_context character.rules_context_label
  json.class_name character.character_class&.name || character.nimble_class
  json.ancestry_name character.ancestry&.name || character.race
  json.current_hp character.trait_set&.current_hp
  json.max_hp character.trait_set&.max_hp
  json.url character_url(character, format: :json)
end
