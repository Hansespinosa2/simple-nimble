# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_23_000823) do
  create_table "characters", force: :cascade do |t|
    t.string "name"
    t.string "race"
    t.string "nimble_class"
    t.integer "level"
    t.string "background"
    t.text "description"
    t.string "languages"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "skills", force: :cascade do |t|
    t.string "name"
    t.integer "value"
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_skills_on_character_id"
  end

  create_table "spells", force: :cascade do |t|
    t.string "school"
    t.string "name"
    t.integer "tier"
    t.integer "target"
    t.integer "action_cost"
    t.integer "range"
    t.string "damage"
    t.text "description"
    t.integer "casting_time"
    t.text "high_level"
    t.text "upcast"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "stats", force: :cascade do |t|
    t.string "name"
    t.integer "value"
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_stats_on_character_id"
  end

  create_table "trait_sets", force: :cascade do |t|
    t.integer "character_id", null: false
    t.integer "initiative"
    t.integer "speed"
    t.string "hit_die"
    t.integer "current_hit_dice"
    t.integer "max_hit_dice"
    t.integer "current_actions"
    t.integer "max_actions"
    t.integer "armor"
    t.integer "temp_hp"
    t.integer "current_hp"
    t.integer "max_hp"
    t.integer "current_wounds"
    t.integer "max_wounds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_trait_sets_on_character_id"
  end

  add_foreign_key "skills", "characters"
  add_foreign_key "stats", "characters"
  add_foreign_key "trait_sets", "characters"
end
