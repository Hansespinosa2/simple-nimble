# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

Character.create(
  name: "Gorn",
  race: "Orc",
  nimble_class: "Zephyr",
  level: 5,
  background: "Angry",
  description: "Gorn is a fierce orc Zephyr, known for his swift movements and relentless aggression. His imposing presence and quick temper make him a formidable opponent on the battlefield.",
  languages: "Common, Orcish"
)

Character.create(
  name: 'Luna Banana-Hammock',
  race: "Birdfolk",
  nimble_class: "Stormweaver",
  level: 10,
  background: "Inspirational leader",
  description: "Luna is the lone survivor of an ancient birdfolk civilization, carrying the wisdom and sorrow of her lost people. Her resilience and leadership inspire those around her, and her mastery of storm magic reflects the enduring spirit of her heritage.",
  languages: "Common, Bird, Elvish"
)
