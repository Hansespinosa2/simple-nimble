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

ActiveRecord::Schema[8.1].define(version: 2026_09_25_100000) do
  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "email"
    t.string "role", default: "player", null: false
    t.string "session_token", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_accounts_on_email", unique: true
    t.index ["session_token"], name: "index_accounts_on_session_token", unique: true
  end

  create_table "ancestries", force: :cascade do |t|
    t.integer "all_skills_bonus", default: 0, null: false
    t.integer "armor_modifier", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "initiative_modifier", default: 0, null: false
    t.text "language_grants"
    t.integer "max_hit_dice_modifier", default: 0, null: false
    t.integer "max_wounds_modifier", default: 0, null: false
    t.string "name"
    t.string "size"
    t.text "skill_modifiers"
    t.integer "speed_modifier", default: 0, null: false
    t.text "trait_summary"
    t.datetime "updated_at", null: false
  end

  create_table "backgrounds", force: :cascade do |t|
    t.integer "armor_modifier", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "initiative_modifier", default: 0, null: false
    t.text "language_grants"
    t.integer "max_hit_dice_modifier", default: 0, null: false
    t.integer "max_wounds_modifier", default: 0, null: false
    t.string "name"
    t.integer "prerequisite_max"
    t.string "prerequisite_stat"
    t.text "skill_modifiers"
    t.datetime "updated_at", null: false
  end

  create_table "campaign_memberships", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "campaign_id", null: false
    t.datetime "created_at", null: false
    t.string "role", default: "player", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_campaign_memberships_on_account_id"
    t.index ["campaign_id", "account_id"], name: "index_campaign_memberships_on_campaign_id_and_account_id", unique: true
    t.index ["campaign_id"], name: "index_campaign_memberships_on_campaign_id"
  end

  create_table "campaigns", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "invite_code", null: false
    t.string "name", null: false
    t.integer "owner_account_id", null: false
    t.datetime "updated_at", null: false
    t.index ["invite_code"], name: "index_campaigns_on_invite_code", unique: true
    t.index ["owner_account_id"], name: "index_campaigns_on_owner_account_id"
  end

  create_table "character_classes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hit_die"
    t.string "key_stat_one"
    t.string "key_stat_two"
    t.string "name"
    t.string "save_bonus_stat"
    t.string "save_penalty_stat"
    t.integer "starting_hp"
    t.datetime "updated_at", null: false
  end

  create_table "character_revisions", force: :cascade do |t|
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.integer "from_level"
    t.text "snapshot", null: false
    t.string "summary"
    t.integer "to_level"
    t.datetime "updated_at", null: false
    t.index ["character_id", "created_at"], name: "index_character_revisions_on_character_id_and_created_at"
    t.index ["character_id"], name: "index_character_revisions_on_character_id"
  end

  create_table "character_shares", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_account_id"
    t.string "permission", default: "read", null: false
    t.string "share_token", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_character_shares_on_campaign_id"
    t.index ["character_id", "campaign_id"], name: "index_character_shares_on_character_id_and_campaign_id", unique: true
    t.index ["character_id"], name: "index_character_shares_on_character_id"
    t.index ["created_by_account_id"], name: "index_character_shares_on_created_by_account_id"
    t.index ["share_token"], name: "index_character_shares_on_share_token", unique: true
  end

  create_table "character_spells", force: :cascade do |t|
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.integer "spell_id", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id", "spell_id"], name: "index_character_spells_on_character_and_spell", unique: true
    t.index ["character_id"], name: "index_character_spells_on_character_id"
    t.index ["spell_id"], name: "index_character_spells_on_spell_id"
  end

  create_table "characters", force: :cascade do |t|
    t.integer "account_id"
    t.integer "ancestry_id"
    t.integer "background_id"
    t.boolean "bonescythe_summoned", default: false, null: false
    t.integer "character_class_id"
    t.text "conditions"
    t.datetime "created_at", null: false
    t.integer "current_gold", default: 0, null: false
    t.text "description"
    t.datetime "encounter_started_at"
    t.text "feature_choices"
    t.text "feature_language_choices", default: "{}", null: false
    t.text "game_notes"
    t.text "inventory"
    t.text "language_choices", default: "[]", null: false
    t.string "languages"
    t.string "legacy_background_text"
    t.integer "level"
    t.string "name"
    t.string "nimble_class"
    t.string "race"
    t.integer "ruleset_version_id"
    t.text "spell_choices"
    t.string "spell_school_choice"
    t.text "starting_equipment"
    t.string "starting_equipment_choice", default: "class_gear", null: false
    t.string "stat_array"
    t.text "stat_assignments"
    t.string "status", default: "draft", null: false
    t.text "subclass_choices", default: "{}", null: false
    t.string "subclass_name"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_characters_on_account_id"
    t.index ["ancestry_id"], name: "index_characters_on_ancestry_id"
    t.index ["background_id"], name: "index_characters_on_background_id"
    t.index ["character_class_id"], name: "index_characters_on_character_class_id"
    t.index ["ruleset_version_id"], name: "index_characters_on_ruleset_version_id"
    t.index ["status"], name: "index_characters_on_status"
  end

  create_table "inventory_items", force: :cascade do |t|
    t.integer "catalog_slots"
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.boolean "equipped", default: false, null: false
    t.string "name", null: false
    t.integer "slots", default: 1, null: false
    t.string "source_ref"
    t.boolean "starting_gear", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["character_id", "starting_gear"], name: "index_inventory_items_on_character_id_and_starting_gear"
    t.index ["character_id"], name: "index_inventory_items_on_character_id"
  end

  create_table "level_ups", force: :cascade do |t|
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.text "feature_choices"
    t.text "feature_language_choices", default: "{}", null: false
    t.datetime "finalized_at"
    t.integer "from_level", null: false
    t.integer "hit_die_roll_one"
    t.integer "hit_die_roll_two"
    t.text "language_choices", default: "[]", null: false
    t.text "notes"
    t.text "preview"
    t.string "second_stat_name"
    t.string "skill_from"
    t.string "skill_name"
    t.text "spell_choices"
    t.string "stat_name"
    t.string "status", default: "draft", null: false
    t.string "subclass_name"
    t.integer "to_level", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id", "status"], name: "index_level_ups_on_character_id_and_status"
    t.index ["character_id"], name: "index_level_ups_on_character_id"
  end

  create_table "ruleset_versions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "published_at"
    t.string "source_reference"
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["name", "version"], name: "index_ruleset_versions_on_name_and_version", unique: true
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
    t.text "class_restriction"
    t.string "condition_applied"
    t.datetime "created_at", null: false
    t.string "damage"
    t.text "description"
    t.text "high_level"
    t.integer "mana_cost"
    t.string "name"
    t.integer "range"
    t.string "range_or_reach"
    t.string "school"
    t.text "source_quote"
    t.string "source_ref"
    t.integer "target"
    t.string "target_type"
    t.integer "tier"
    t.text "upcast"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_spells_on_name_unique", unique: true
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

  create_table "story_subclass_changes", force: :cascade do |t|
    t.integer "approved_by_account_id", null: false
    t.integer "campaign_id", null: false
    t.integer "character_id", null: false
    t.integer "character_revision_id", null: false
    t.datetime "created_at", null: false
    t.string "from_subclass", null: false
    t.string "source_ref", null: false
    t.text "story_note", null: false
    t.text "subclass_choices", default: "{}", null: false
    t.string "to_subclass", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_account_id"], name: "index_story_subclass_changes_on_approved_by_account_id"
    t.index ["campaign_id"], name: "index_story_subclass_changes_on_campaign_id"
    t.index ["character_id", "created_at"], name: "index_story_subclass_changes_on_character_and_created_at"
    t.index ["character_id"], name: "index_story_subclass_changes_on_character_id"
    t.index ["character_revision_id"], name: "index_story_subclass_changes_on_character_revision_id"
  end

  create_table "trait_sets", force: :cascade do |t|
    t.integer "armor"
    t.integer "character_id", null: false
    t.datetime "created_at", null: false
    t.integer "current_actions"
    t.integer "current_hit_dice"
    t.integer "current_hp"
    t.integer "current_mana"
    t.integer "current_resource"
    t.integer "current_wounds"
    t.string "hit_die"
    t.integer "initiative"
    t.integer "inventory_slots"
    t.integer "max_actions"
    t.integer "max_hit_dice"
    t.integer "max_hp"
    t.integer "max_mana"
    t.integer "max_resource"
    t.integer "max_wounds"
    t.string "resource_die"
    t.string "resource_formula"
    t.string "resource_name"
    t.text "resource_tracks"
    t.integer "save_dc"
    t.integer "speed"
    t.integer "temp_hp"
    t.datetime "updated_at", null: false
    t.index ["character_id"], name: "index_trait_sets_on_character_id"
  end

  add_foreign_key "campaign_memberships", "accounts"
  add_foreign_key "campaign_memberships", "campaigns"
  add_foreign_key "campaigns", "accounts", column: "owner_account_id"
  add_foreign_key "character_revisions", "characters"
  add_foreign_key "character_shares", "accounts", column: "created_by_account_id"
  add_foreign_key "character_shares", "campaigns"
  add_foreign_key "character_shares", "characters"
  add_foreign_key "character_spells", "characters"
  add_foreign_key "character_spells", "spells"
  add_foreign_key "characters", "accounts"
  add_foreign_key "characters", "ancestries"
  add_foreign_key "characters", "backgrounds"
  add_foreign_key "characters", "character_classes"
  add_foreign_key "characters", "ruleset_versions"
  add_foreign_key "inventory_items", "characters"
  add_foreign_key "level_ups", "characters"
  add_foreign_key "skill_sets", "characters"
  add_foreign_key "stat_sets", "characters"
  add_foreign_key "story_subclass_changes", "accounts", column: "approved_by_account_id"
  add_foreign_key "story_subclass_changes", "campaigns"
  add_foreign_key "story_subclass_changes", "character_revisions"
  add_foreign_key "story_subclass_changes", "characters"
  add_foreign_key "trait_sets", "characters"
end
