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

ActiveRecord::Schema[8.1].define(version: 2025_09_05_025007) do
  create_table "character_spells", force: :cascade do |t|
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.integer "spell_id", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_character_spells_on_character_id"
    t.index ["spell_id"], name: "index_character_spells_on_spell_id"
  end

  create_table "characters", force: :cascade do |t|
    t.string "background"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "languages"
    t.integer "level"
    t.string "name"
    t.string "nimble_class"
    t.string "race"
    t.datetime "updated_at", null: false
  end

  create_table "skill_sets", force: :cascade do |t|
    t.integer "arcana"
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.integer "examination"
    t.integer "finesse"
    t.integer "influence"
    t.integer "insight"
    t.integer "lore"
    t.integer "might"
    t.integer "naturecraft"
    t.integer "perception"
    t.integer "stealth"
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_skill_sets_on_character_id"
  end

  create_table "spells", force: :cascade do |t|
    t.integer "action_cost"
    t.integer "casting_time"
    t.datetime "created_at", null: false
    t.string "damage"
    t.text "description"
    t.text "high_level"
    t.string "name"
    t.integer "range"
    t.string "school"
    t.integer "target"
    t.integer "tier"
    t.text "upcast"
    t.datetime "updated_at", null: false
  end

  create_table "stat_sets", force: :cascade do |t|
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.integer "dexterity"
    t.integer "intelligence"
    t.integer "strength"
    t.datetime "updated_at", null: false
    t.integer "will"
    t.index ["character_id"], name: "index_stat_sets_on_character_id"
  end

  create_table "trait_sets", force: :cascade do |t|
    t.integer "armor"
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.integer "current_actions"
    t.integer "current_hit_dice"
    t.integer "current_hp"
    t.integer "current_wounds"
    t.string "hit_die"
    t.integer "initiative"
    t.integer "max_actions"
    t.integer "max_hit_dice"
    t.integer "max_hp"
    t.integer "max_wounds"
    t.integer "speed"
    t.integer "temp_hp"
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_trait_sets_on_character_id"
  end

  add_foreign_key "character_spells", "characters"
  add_foreign_key "character_spells", "spells"
  add_foreign_key "skill_sets", "characters"
  add_foreign_key "stat_sets", "characters"
  add_foreign_key "trait_sets", "characters"
end
