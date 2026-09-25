payload = @character.snapshot_payload

json.format CharacterImportService::FORMAT_NAME
json.format_version CharacterImportService::FORMAT_VERSION
json.character payload.fetch("character").merge("id" => @character.id)
json.rules payload.fetch("rules")
json.progression payload.fetch("progression")
json.stats payload.fetch("stats")
json.skills payload.fetch("skills")
json.traits payload.fetch("traits")
json.spells payload.fetch("spells")
json.inventory_items payload.fetch("inventory_items")
json.creation @character.import_creation_snapshot
json.level_ups @character.interchange_level_ups
json.status_label @character.status_label
json.url character_url(@character, format: :json)
