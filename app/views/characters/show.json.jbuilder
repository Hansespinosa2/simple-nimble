payload = @character.snapshot_payload

json.character payload.fetch("character").merge("id" => @character.id)
json.rules payload.fetch("rules")
json.stats payload.fetch("stats")
json.skills payload.fetch("skills")
json.traits payload.fetch("traits")
json.spells payload.fetch("spells")
json.status_label @character.status_label
json.url character_url(@character, format: :json)
