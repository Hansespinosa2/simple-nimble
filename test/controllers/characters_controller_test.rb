require "test_helper"

# S-01:AC-1 S-01:AC-3 S-01:AC-4 S-05:AC-1 S-05:AC-3 S-05:AC-4 S-05:AC-5 S-06:AC-6 S-07:AC-4 S-07:AC-6 S-09:AC-3
class CharactersControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed if Character.count.zero?
    @character_class = CharacterClass.find_by!(name: "Berserker")
    @ancestry = Ancestry.find_by!(name: "Human")
    @background = Background.find_by!(name: "Fearless")
    @ruleset = RulesetVersion.active.first
    @character = Character.create!(
      name: "Test Hero",
      description: "A brave adventurer seeking glory.",
      level: 1,
      legacy_background_text: "Soldier",
      race: "Human",
      nimble_class: "Warrior",
      languages: "Common, Elvish"
    )
  end

  test "should get index" do
    get characters_url
    assert_response :success
    assert_select "h1", "Your heroes"
    assert_includes response.body, @character.name
  end

  test "should get new" do
    get new_character_url
    assert_response :success
    assert_select "select[name='character[character_class_id]']"
    assert_select "select[name='character[ancestry_id]']"
    assert_select "select[name='character[background_id]']"
    assert_select "select[name='character[stat_array]']"
    assert_select ".skill-rule-note", /explicitly grant.*Songweaver's Jack of All Trades.*Safe Rest.*Core Rules 2\.0\.1, p\. 21/
    assert_select "select[name='character[starting_equipment_choice]'] option[value='starting_gold']", text: "Starting gold instead (50 gp per level)"
    assert_select "select[name='character[stat_assignments][strength]']"
    assert_select "select[name='character[stat_assignments][will]']"
    assert_select "[data-character-builder-target='savesPreview']"
    assert_select "strong[data-character-builder-target='hpPreview']", text: "—"
    assert_select "strong[data-character-builder-target='hitDiePreview']", text: "—"
    assert_select "[data-character-builder-target='backgroundSpellChoiceField'][hidden]"
    assert_select "select[name='character[spell_choices][Academy Dropout][1][]'] option[value='Firebrand']"
    rules_payload = JSON.parse(Nokogiri::HTML(response.body).at_css("form.builder-form")["data-character-builder-rules-value"])
    academy_background_id = Background.find_by!(name: "Academy Dropout").id.to_s
    retirement_background_id = Background.find_by!(name: "Back Out of Retirement").id.to_s
    assert_equal true, rules_payload.dig("backgrounds", academy_background_id, "starting_spell_choice")
    assert_equal "Utility Spell", rules_payload.dig("backgrounds", academy_background_id, "starting_spell_choice_rule", "choice_label")
    assert_equal 1, rules_payload.dig("backgrounds", academy_background_id, "starting_spell_choice_rule", "count")
    assert_includes rules_payload.dig("backgrounds", retirement_background_id, "feature_note", "manual_effect"), "Take 1 Wound"
    assert_equal "Core Rules 2.0.1, p. 28", rules_payload.dig("backgrounds", retirement_background_id, "feature_note", "source_ref")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "the character sheet shows source-backed guidance for non-automated background effects" do
    retiree = Character.create!(
      name: "Retirement Rules Hero",
      character_class: @character_class,
      ancestry: @ancestry,
      background: Background.find_by!(name: "Back Out of Retirement"),
      stat_array: "balanced"
    )

    get character_url(retiree)

    assert_response :success
    assert_select ".background-rules-note", /not automatically resolved/
    assert_select ".background-rules-note", /Take 1 Wound.*Core Rules 2\.0\.1, p\. 28/
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-1 S-09:AC-3
  test "creation rule hints and skill input limits follow the catalog" do
    catalog = Rules::NimbleCatalog.data
    original_arrays = catalog.fetch("stat_arrays")
    original_derived_values = catalog.fetch("derived_values")
    original_starting_equipment = catalog.fetch("starting_equipment")
    changed_arrays = original_arrays.deep_dup
    changed_arrays["standard"] = [ 4, 2, 1, -2 ]
    catalog["stat_arrays"] = changed_arrays
    catalog["derived_values"] = original_derived_values.merge("max_skill" => 17)
    catalog["starting_equipment"] = original_starting_equipment.merge("gold_per_level" => 75)

    begin
      get new_character_url

      assert_response :success
      assert_select ".stat-array-rules-summary", /Standard \+4\/\+2\/\+1\/-2/
      assert_select ".panel-subtitle", /Skills cannot exceed \+17\./
      assert_select "input[data-skill='might'][max='17']"
      assert_select "select[name='character[starting_equipment_choice]'] option[value='starting_gold']", text: "Starting gold instead (75 gp per level)"
      assert_select ".field-hint", /choose listed class gear or 75 gp per starting level/
    ensure
      catalog["stat_arrays"] = original_arrays
      catalog["derived_values"] = original_derived_values
      catalog["starting_equipment"] = original_starting_equipment
    end
  end

  # S-02:AC-1 S-02:AC-4 S-09:AC-3
  test "inventory slot guidance follows canonical capacity and currency values" do
    catalog = Rules::NimbleCatalog.data
    original_starting_equipment = catalog.fetch("starting_equipment")
    catalog["starting_equipment"] = original_starting_equipment.merge(
      "gold_per_inventory_slot" => 600,
      "gold_per_inventory_slot_source_quote" => "600 gp"
    )

    begin
      get character_url(@character)

      assert_response :success
      assert_select ".inventory-rule-note p", /Each hero has #{Character::BASE_INVENTORY_SLOTS} \+ STR inventory slots/
      assert_select ".inventory-rule-note p", /600 gp/
    ensure
      catalog["starting_equipment"] = original_starting_equipment
    end
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "the sheet save DC formula caption follows the catalog base" do
    catalog = Rules::NimbleCatalog.data
    original_derived_values = catalog.fetch("derived_values")
    catalog["derived_values"] = original_derived_values.merge("save_dc_base" => 14)

    begin
      get character_url(@character)

      assert_response :success
      assert_select ".save-dc-formula", text: "14 + KEY"
    ensure
      catalog["derived_values"] = original_derived_values
    end
  end

  # S-02:AC-1 S-02:AC-4 S-09:AC-3
  test "the initiative formula caption follows the rules catalog" do
    catalog = Rules::NimbleCatalog.data
    original_derived_values = catalog.fetch("derived_values")
    catalog["derived_values"] = original_derived_values.merge("initiative_formula" => "WIL")

    begin
      get character_url(@character)

      assert_response :success
      assert_select ".vital-card .vital-foot", text: "WIL + origin", count: 1
    ensure
      catalog["derived_values"] = original_derived_values
    end
  end

  # S-02:AC-1 S-02:AC-2 S-07:AC-2 S-09:AC-3
  test "rest guidance and action labels follow catalog values" do
    catalog = Rules::NimbleCatalog.data
    original_resting_rules = catalog.fetch("resting")
    changed_resting_rules = original_resting_rules.deep_dup
    changed_resting_rules.fetch("safe_rest")["wounds_healed"] = 2
    changed_resting_rules.fetch("field_rests").fetch("catch_breath")["minimum_duration"] = 15
    changed_resting_rules.fetch("field_rests").fetch("make_camp")["minimum_duration"] = 9
    catalog["resting"] = changed_resting_rules

    begin
      hero = Character.create!(
        name: "Rest Guidance Hero",
        character_class: CharacterClass.find_by!(name: "Mage"),
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        stat_array: "balanced"
      )
      get character_url(hero)

      assert_response :success
      assert_select ".safe-rest-summary", /heal 2 Wounds/
      assert_select ".field-rest-summary", /Catch Breath takes at least 15 minutes.*Make Camp takes at least 9 hours with food and sleep/
      assert_select "form[action='#{field_rest_character_path(hero)}'] input[type='submit']", value: "Catch Breath · 15 min"
      assert_select "form[action='#{field_rest_character_path(hero)}'] input[type='submit']", value: "Make Camp · 9 hours"
    ensure
      catalog["resting"] = original_resting_rules
    end
  end

  test "should embed structured origin rules in the builder payload" do
    get new_character_url

    assert_response :success
    assert_includes response.body, "skill_modifiers"
    assert_includes response.body, "language_grants"
    assert_includes response.body, "initiative_modifier"
    assert_includes response.body, "save_bonus"
    assert_includes response.body, "save_penalty"
  end

  test "should create character" do
    assert_difference("Character.count") do
      post characters_url, params: { character: { legacy_background_text: "A new beginning", description: "A different hero.", languages: "Common", level: 1, name: "Created Hero", nimble_class: "Scout", race: "Elf" } }
    end

    created = Character.order(:id).last
    assert_redirected_to character_url(created)
    assert_equal "Created Hero", created.name
    assert_equal "A different hero.", created.description
    assert_equal "A new beginning", created.legacy_background_text
    assert created.draft?
    assert created.character_revisions.exists?(event_type: "created")
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-1 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "should create a higher-level character with source-defined starting gold" do
    post characters_url, params: {
      character: canonical_character_attributes.merge(
        name: "Gold-funded Hero",
        level: 3,
        starting_equipment_choice: "starting_gold"
      )
    }

    character = Character.order(:id).last
    assert_redirected_to character_url(character)
    assert_equal "starting_gold", character.starting_equipment_choice
    assert_equal 150, character.current_gold
    assert_equal "150 gp", character.starting_equipment
    assert_equal 1, character.inventory_slots_used
    assert_equal 150, character.character_revisions.order(:id).last.snapshot.dig("character", "current_gold")
  end

  test "a draft gold allowance scales when its starting level is changed" do
    character = Character.create!(
      name: "Level Change Draft",
      character_class: @character_class,
      starting_equipment_choice: "starting_gold"
    )
    assert_equal 50, character.current_gold

    patch character_url(character), params: { character: { level: 4 } }

    assert_redirected_to character_url(character)
    assert_equal 200, character.reload.current_gold
  end

  test "the game tracker saves current gold and counts its carrying slots" do
    patch tracker_character_url(@character), params: { character: { current_gold: 501 } }

    assert_redirected_to character_url(@character)
    assert_equal 501, @character.reload.current_gold
    assert_equal 2, @character.inventory_slots_used
    assert_equal 501, @character.character_revisions.order(:id).last.snapshot.dig("character", "current_gold")
  end

  test "should finalize a legal character and persist derived values" do
    # The finalize flag is a top-level form control, just as the real form submits it.
    assert_difference("Character.count") do
      post characters_url, params: { character: canonical_character_attributes.merge(name: "Playable Hero"), finalize: "1" }
    end

    created = Character.order(:id).last
    assert_redirected_to character_url(created)
    assert created.playable?
    assert_equal @character_class, created.character_class
    assert_equal @ancestry, created.ancestry
    assert_equal @background, created.background
    assert_equal "balanced", created.stat_array
    assert_equal @character_class.starting_hp, created.trait_set.max_hp
    assert created.character_revisions.exists?(event_type: "finalized")
  end

  test "a playable character cannot switch its starting equipment path afterward" do
    post characters_url, params: {
      character: canonical_character_attributes.merge(name: "Locked Starter")
        .merge(character_class_id: @character_class.id, ancestry_id: @ancestry.id, background_id: @background.id),
      finalize: "1"
    }
    character = Character.order(:id).last
    assert character.playable?

    patch character_url(character), params: { character: { starting_equipment_choice: "starting_gold" } }

    assert_response :unprocessable_entity
    assert_includes response.body, "can only be changed while the character is a draft"
    assert_equal "class_gear", character.reload.starting_equipment_choice
    assert_equal 0, character.current_gold
  end

  # S-04:AC-6 S-05:AC-2 S-09:AC-3
  test "a playable character rejects rules and progression edits at the request boundary" do
    character = Character.create!(canonical_character_attributes.merge(name: "Rules Locked Hero"))
    character.finalize_creation!
    original = {
      character_class_id: character.character_class_id,
      ancestry_id: character.ancestry_id,
      background_id: character.background_id,
      stat_array: character.stat_array,
      stat_assignments: character.stat_assignments.deep_dup,
      languages: character.languages,
      language_choices: character.language_choices.deep_dup,
      skills: character.skill_set.attributes.slice(*Character::SKILL_NAMES.map(&:to_s)),
      spells: character.spells.ids,
      revisions: character.character_revisions.count
    }

    patch character_url(character), params: {
      character: {
        character_class_id: CharacterClass.find_by!(name: "Mage").id,
        ancestry_id: Ancestry.find_by!(name: "Orc").id,
        background_id: Background.find_by!(name: "Academy Dropout").id,
        stat_array: "min_max",
        stat_assignments: { strength: 3, dexterity: 1, intelligence: -1, will: -1 },
        language_choices: [ "Goblin" ],
        feature_language_choices: { "Some Feature" => [ "Goblin" ] },
        skill_set_attributes: { id: character.skill_set.id, might: 2 },
        spell_choices: { "Academy Dropout" => { "1" => [ "Firebrand" ] } },
        spell_ids: [ Spell.order(:id).first.id ]
      }
    }

    assert_response :bad_request
    assert_includes response.body, "locked to preserve its level history"
    character.reload
    assert_equal original.fetch(:character_class_id), character.character_class_id
    assert_equal original.fetch(:ancestry_id), character.ancestry_id
    assert_equal original.fetch(:background_id), character.background_id
    assert_equal original.fetch(:stat_array), character.stat_array
    assert_equal original.fetch(:stat_assignments), character.stat_assignments
    assert_equal original.fetch(:languages), character.languages
    assert_equal original.fetch(:language_choices), character.language_choices
    assert_equal original.fetch(:skills), character.skill_set.attributes.slice(*Character::SKILL_NAMES.map(&:to_s))
    assert_equal original.fetch(:spells), character.spells.ids
    assert_equal original.fetch(:revisions), character.character_revisions.count
  end

  # S-04:AC-3 S-10:AC-3 S-10:AC-9 S-09:AC-3
  test "a higher-level imported draft cannot edit its replayed build" do
    character = Character.create!(canonical_character_attributes.merge(name: "Imported Locked Hero", level: 2))
    character.record_revision!(event_type: "imported", summary: "Imported verified progression")

    assert character.draft?
    assert character.rules_progression_locked?

    patch character_url(character), params: { character: { ancestry_id: Ancestry.find_by!(name: "Orc").id } }

    assert_response :bad_request
    assert_equal @ancestry.id, character.reload.ancestry_id
  end

  # S-04:AC-6 S-09:AC-3
  test "a playable character can still save identity and story-note edits" do
    character = Character.create!(canonical_character_attributes.merge(name: "Editable Identity Hero"))
    character.finalize_creation!

    patch character_url(character), params: {
      character: {
        name: "Renamed Playable Hero",
        description: "The same build, with a new chapter.",
        legacy_background_text: "A promise kept on the northern road."
      }
    }

    assert_redirected_to character_url(character)
    character.reload
    assert_equal "Renamed Playable Hero", character.name
    assert_equal "The same build, with a new chapter.", character.description
    assert_equal "A promise kept on the northern road.", character.legacy_background_text
    assert_equal @character_class.id, character.character_class_id
    assert_equal @ancestry.id, character.ancestry_id
    assert_equal @background.id, character.background_id
  end

  test "should save an Academy Dropout Utility Spell choice when finalizing" do
    post characters_url, params: {
      character: canonical_character_attributes.merge(
        name: "Academy Spell Hero",
        background_id: Background.find_by!(name: "Academy Dropout").id,
        spell_choices: { "Academy Dropout" => { "1" => "Wind Whisper" } }
      ),
      finalize: "1"
    }

    assert_redirected_to character_url(Character.order(:id).last)
    created = Character.order(:id).last
    assert created.playable?
    assert_includes created.spells.pluck(:name), "Wind Whisper"
    assert_equal [ "Wind Whisper" ], created.recorded_spell_choices.fetch("Academy Dropout")
  end

  # S-02:AC-1 S-02:AC-4 S-05:AC-1 S-05:AC-3 S-09:AC-3
  test "creation accepts and grants multiple catalog-defined background spell choices" do
    catalog = Rules::NimbleCatalog.data
    original_choices = catalog.fetch("background_spell_choices")
    background_name = "Wayward Apprentice"
    background = Background.create!(name: background_name)
    catalog["background_spell_choices"] = original_choices.merge(
      background_name => {
        "source_ref" => "Test rules, p. 1",
        "source_quote" => "Learn 2 different Utility Spells.",
        "kind" => "utility_spell_any",
        "choice_label" => "Utility Spell",
        "count" => 2,
        "distinct" => true
      }
    )

    begin
      post characters_url, params: {
        character: canonical_character_attributes.merge(
          name: "Two-Spell Background Hero",
          background_id: background.id,
          spell_choices: { background_name => { "1" => [ "Wind Whisper", "Firebrand" ] } }
        ),
        finalize: "1"
      }

      assert_redirected_to character_url(Character.order(:id).last)
      created = Character.order(:id).last
      assert created.playable?
      assert_equal [ "Firebrand", "Wind Whisper" ], created.recorded_spell_choices.fetch(background_name).sort
      assert_equal [ "Firebrand", "Wind Whisper" ], created.spells.merge(Spell.utility).pluck(:name).sort
    ensure
      catalog["background_spell_choices"] = original_choices
    end
  end

  test "should explain the Academy Dropout Utility Spell requirement when missing" do
    post characters_url, params: {
      character: canonical_character_attributes.merge(
        name: "Missing Academy Spell Hero",
        background_id: Background.find_by!(name: "Academy Dropout").id
      ),
      finalize: "1"
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Academy Dropout requires 1 Utility Spell choice."
    assert_includes response.body, "Core Rules 2.0.1, p. 28"
  end

  test "should persist the selected stat placement from the builder" do
    attributes = canonical_character_attributes.merge(
      name: "Placed Hero",
      stat_assignments: { strength: 0, dexterity: 1, intelligence: 1, will: 2 }
    )

    post characters_url, params: { character: attributes }

    assert_redirected_to character_url(Character.order(:id).last)
    created = Character.order(:id).last
    assert_equal 0, created.stat_set.strength
    assert_equal 1, created.stat_set.dexterity
    assert_equal 1, created.stat_set.intelligence
    assert_equal 2, created.stat_set.will
  end

  test "should keep an incomplete character as a draft and render every blocking reason" do
    assert_difference("Character.count") do
      post characters_url, params: { character: { name: "Blocked Hero" }, finalize: "1" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Choose a class before finalizing."
    assert_includes response.body, "Choose an ancestry before finalizing."
    assert_includes response.body, "Choose a background before finalizing."
    assert_includes response.body, "Choose a stat array before finalizing."
    assert Character.find_by(name: "Blocked Hero").draft?
  end

  test "should show character" do
    get character_url(@character)
    assert_response :success
    assert_select "h1", @character.name
    assert_includes response.body, @character.description
  end

  test "should return a useful character index payload" do
    get characters_url(format: :json)

    assert_response :success
    payload = JSON.parse(response.body)
    entry = payload.find { |row| row.fetch("id") == @character.id }

    assert_equal @character.name, entry.fetch("name")
    assert_equal "draft", entry.fetch("status")
    assert_equal "Warrior", entry.fetch("class_name")
    assert_equal "Human", entry.fetch("ancestry_name")
    assert_nil entry.fetch("current_hp")
    assert_match %r{/characters/#{@character.id}\.json\z}, entry.fetch("url")
  end

  test "should return a complete character sheet payload" do
    get character_url(@character, format: :json)

    assert_response :success
    payload = JSON.parse(response.body)

    assert_equal @character.id, payload.dig("character", "id")
    assert_equal @character.name, payload.dig("character", "name")
    assert_equal "Nimble v2.0.1", payload.dig("rules", "ruleset")
    assert_equal [], payload.dig("progression", "class_features")
    assert_equal @character.stat_set.strength, payload.dig("stats", "strength")
    assert_equal @character.skill_set.might, payload.dig("skills", "might")
    assert_nil payload.dig("traits", "max_hp")
    assert_equal [], payload.fetch("spells")
    assert_equal CharacterImportService::FORMAT_NAME, payload.fetch("format")
    assert_equal CharacterImportService::FORMAT_VERSION, payload.fetch("format_version")
    assert_equal 1, payload.dig("creation", "character", "level")
    assert_equal [], payload.fetch("level_ups")
    assert_equal [], payload.fetch("inventory_items")
    assert_equal "Draft", payload.fetch("status_label")
  end

  test "JSON sheet payload includes recorded feature choices" do
    @character.update!(
      character_class: @character_class,
      ancestry: @ancestry,
      background: @background,
      stat_array: "standard",
      level: 4,
      feature_choices: { "Savage Arsenal" => [ "Death Blow" ] }
    )

    get character_url(@character, format: :json)

    assert_response :success
    payload = JSON.parse(response.body)
    choice = payload.fetch("progression").fetch("feature_choices").first
    assert_equal "Savage Arsenal", choice.fetch("name")
    assert_equal [ "Death Blow" ], choice.fetch("selected")
  end

  test "should get edit" do
    get edit_character_url(@character)
    assert_response :success
  end

  test "editing a legacy character does not erase its languages before the player confirms explicit choices" do
    get edit_character_url(@character)

    assert_response :success
    assert_select "input[type='hidden'][name='character[language_choices][]']", 0

    patch character_url(@character), params: { character: { name: "Legacy Hero, Remembered" } }

    assert_redirected_to character_url(@character)
    assert_equal "Common, Elvish", @character.reload.languages
    assert_empty @character.language_choices
  end

  test "a playable character's level is read-only in the general editor" do
    character = Character.create!(canonical_character_attributes.merge(name: "Level-Up Only Hero"))
    character.finalize_creation!

    get edit_character_url(character)

    assert_response :success
    assert_select "#character_level[disabled]"
    assert_includes response.body, "Level changes happen through the explicit Level up flow."
  end

  test "should update character" do
    patch character_url(@character), params: { character: { legacy_background_text: "Updated story", description: "Now with a real plan.", languages: "Common, Dwarvish", level: 2, name: "Updated Hero", nimble_class: "Guardian", race: "Dwarf" } }

    assert_redirected_to character_url(@character)
    @character.reload
    assert_equal "Updated Hero", @character.name
    assert_equal "Now with a real plan.", @character.description
    assert_equal "Updated story", @character.legacy_background_text
    assert_equal 2, @character.level
    assert_equal "Edited", @character.character_revisions.order(:id).last.event_label
  end

  # S-04:AC-3 S-06:AC-6 S-09:AC-1 S-09:AC-3
  test "should reject a direct level edit outside the explicit level-up flow" do
    character = Character.create!(canonical_character_attributes.merge(name: "No Shortcut Hero"))
    character.finalize_creation!
    original_revisions = character.character_revisions.count

    patch character_url(character), params: { character: { level: 2 } }

    assert_response :unprocessable_entity
    assert_includes response.body, "can only change through a finalized level-up"
    assert_equal 1, character.reload.level
    assert_equal 7, character.skill_set.might
    assert_equal original_revisions, character.character_revisions.count
  end

  test "should not permit direct derived-field edits outside the explicit flows" do
    character = Character.create!(canonical_character_attributes.merge(name: "Protected Hero"))
    character.finalize_creation!
    original_stats = character.stat_set.attributes.slice("strength", "dexterity", "intelligence", "will")
    original_traits = character.trait_set.attributes.slice("max_hp", "armor", "initiative")

    patch character_url(character), params: {
      character: {
        stat_set_attributes: { id: character.stat_set.id, strength: 99 },
        trait_set_attributes: { id: character.trait_set.id, max_hp: 999, armor: 99, initiative: 99 }
      }
    }

    assert_response :bad_request
    character.reload
    assert_equal original_stats, character.stat_set.attributes.slice("strength", "dexterity", "intelligence", "will")
    assert_equal original_traits, character.trait_set.attributes.slice("max_hp", "armor", "initiative")
  end

  test "should create a character through the JSON endpoint" do
    assert_difference("Character.count") do
      post characters_url(format: :json), params: { character: canonical_character_attributes.merge(name: "JSON Hero") }, as: :json
    end

    assert_response :created
    payload = JSON.parse(response.body)
    created = Character.find_by!(name: "JSON Hero")

    assert_equal created.id, payload.dig("character", "id")
    assert_equal "JSON Hero", payload.dig("character", "name")
    assert_equal "Berserker", payload.dig("rules", "class")
  end

  test "should return JSON rule explanations when finalization is blocked" do
    assert_difference("Character.count") do
      post characters_url(format: :json), params: { character: { name: "Blocked JSON Hero" }, finalize: "1" }, as: :json
    end

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    created = Character.find_by!(name: "Blocked JSON Hero")

    assert created.draft?
    assert_includes payload.fetch("errors"), "Choose a class before finalizing."
    assert_equal "Chapter 2, Class Rules", payload.fetch("explanations").first.fetch("source_ref")
  end

  test "should keep a JSON update draft when finalization is blocked" do
    patch character_url(@character, format: :json), params: { character: { name: "Still a Draft" }, finalize: "1" }, as: :json

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)

    assert_equal "Still a Draft", @character.reload.name
    assert @character.draft?
    assert_includes payload.fetch("errors"), "Choose a class before finalizing."
  end

  test "should destroy character" do
    assert_difference("Character.count", -1) do
      delete character_url(@character)
    end

    assert_redirected_to characters_url
    assert_not Character.exists?(@character.id)
  end

  test "should have stats and skills for each character" do
    Character.find_each do |character|
      assert character.stat_set.persisted?, "#{character.name} should have persisted stats"
      assert character.skill_set.persisted?, "#{character.name} should have persisted skills"
      assert_equal character, character.stat_set.character
      assert_equal character, character.skill_set.character
    end
  end

  test "should save in-game tracker state as a revision" do
    assert_difference("CharacterRevision.where(event_type: 'game_update').count", 1) do
      patch tracker_character_url(@character), params: {
        character: {
          conditions: "Smoldering",
          inventory: "Torch, rope",
          game_notes: "Met the ferryman.",
          trait_set_attributes: {
            id: @character.trait_set.id,
            current_hp: 7,
            temp_hp: 2,
            current_wounds: 1,
            current_actions: 2,
            current_hit_dice: 1
          }
        }
      }
    end

    assert_redirected_to character_url(@character)
    @character.reload
    assert_equal 7, @character.trait_set.current_hp
    assert_equal "Smoldering", @character.conditions
    assert_equal "Torch, rope", @character.inventory
    assert_equal "Met the ferryman.", @character.game_notes
    assert_equal 2, @character.trait_set.temp_hp
    assert_equal 1, @character.trait_set.current_wounds
    assert_equal 2, @character.trait_set.current_actions
    assert_equal "In-game state updated", @character.character_revisions.order(:id).last.summary
    assert_equal "Smoldering", @character.character_revisions.order(:id).last.snapshot.fetch("character").fetch("conditions")
  end

  # S-02:AC-1 S-02:AC-2 S-07:AC-2 S-09:AC-1 S-09:AC-3
  test "tracker applies the catalog zero-HP Wound once per transition and refreshes Wound-triggered resources" do
    hero = Character.create!(
      name: "Zero HP Tracker Hero",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Dragonborn"),
      background: @background,
      stat_array: "balanced"
    )
    wound_resource_key = "ancestry_dragonborn_draconic_heritage"
    hero.trait_set.update!(resource_tracks: hero.trait_set.resource_tracks.map do |track|
      track.fetch("key") == wound_resource_key ? track.merge("current" => 0) : track
    end)
    transition_rule = Rules::NimbleCatalog.zero_hp_transition_rules
    original_transition_rule = transition_rule.dup

    begin
      transition_rule["wounds_gained"] = 2
      transition_rule["source_ref"] = "Test rules, p. 99"
      transition_rule["source_quote"] = "Test rule: gain 2 Wounds when reduced to 0 HP."

      patch tracker_character_url(hero), params: { character: { trait_set_attributes: { id: hero.trait_set.id, current_hp: 0, current_wounds: 0 } } }
      assert_redirected_to character_url(hero)
      assert_equal 2, hero.reload.trait_set.current_wounds
      assert_equal 1, hero.trait_set.resource_tracks.find { |track| track.fetch("key") == wound_resource_key }.fetch("current")
      assert_includes flash[:notice], "added 2 Wounds. Test rules, p. 99"
      assert_includes hero.character_revisions.order(:id).last.summary, "gained 2 Wounds on reaching 0 HP"

      patch tracker_character_url(hero), params: { character: { trait_set_attributes: { id: hero.trait_set.id, current_hp: 0, current_wounds: 2 } } }
      assert_equal 2, hero.reload.trait_set.current_wounds, "remaining at 0 HP must not count as a second drop"

      patch tracker_character_url(hero), params: { character: { trait_set_attributes: { id: hero.trait_set.id, current_hp: 5, current_wounds: 2, resource_tracks: [ { key: wound_resource_key, current: 0 } ] } } }
      assert_equal 0, hero.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == wound_resource_key }.fetch("current")

      patch tracker_character_url(hero), params: { character: { trait_set_attributes: { id: hero.trait_set.id, current_hp: 0, current_wounds: 2, resource_tracks: [ { key: wound_resource_key, current: 0 } ] } } }
      assert_equal 4, hero.reload.trait_set.current_wounds
      assert_equal 1, hero.trait_set.resource_tracks.find { |track| track.fetch("key") == wound_resource_key }.fetch("current")
    ensure
      transition_rule.replace(original_transition_rule)
    end
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Kinetic Momentum starts at level three and grants one Burst per Wound gained" do
    Rails.application.load_seed
    zephyr_class = CharacterClass.find_by!(name: "Zephyr")
    ancestry = Ancestry.find_by!(name: "Human")
    level_two = Character.create!(name: "Untrained Momentum", level: 2, character_class: zephyr_class, ancestry:, background: @background, stat_array: "balanced")
    level_three = Character.create!(name: "Kinetic Momentum", level: 3, character_class: zephyr_class, ancestry:, background: @background, stat_array: "balanced")

    patch tracker_character_url(level_two), params: {
      character: { trait_set_attributes: { id: level_two.trait_set.id, current_wounds: 1, resource_tracks: [ { key: "bursts_of_speed", current: 0 } ] } }
    }
    assert_equal 1, level_two.reload.trait_set.current_wounds
    assert_equal 0, level_two.trait_set.resource_tracks.sole.fetch("current"), "level 2 has not gained Kinetic Momentum yet"

    patch tracker_character_url(level_three), params: {
      character: { trait_set_attributes: { id: level_three.trait_set.id, current_wounds: 2, resource_tracks: [ { key: "bursts_of_speed", current: 0 } ] } }
    }
    assert_equal 2, level_three.reload.trait_set.current_wounds
    assert_equal 2, level_three.trait_set.resource_tracks.sole.fetch("current"), "two Wounds produce two Bursts"
    assert_nil level_three.trait_set.resource_tracks.sole["max"]
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Zephyr tracks Wound gains, Unyielding Resolve, and Kinetic Momentum through encounter changes" do
    Rails.application.load_seed
    zephyr = Character.create!(
      name: "Kinetic Tracker",
      level: 4,
      character_class: CharacterClass.find_by!(name: "Zephyr"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: @background,
      stat_array: "balanced"
    )
    burst_key = "bursts_of_speed"
    dexterity = zephyr.stat_value(:dexterity)
    zephyr.begin_encounter!
    burst_track = zephyr.reload.trait_set.resource_tracks.sole
    assert_nil burst_track["max"]
    assert_equal dexterity, burst_track.fetch("current")

    get character_url(zephyr)
    assert_response :success
    assert_select ".safe-rest-action", /the first Wound you would gain is ignored/i
    assert_select ".safe-rest-action", /still triggers Wound-based abilities such as Kinetic Momentum/i
    assert_select ".safe-rest-action .field-hint", /Ready — the first Wound this encounter will be ignored\./

    patch tracker_character_url(zephyr), params: {
      character: {
        trait_set_attributes: {
          id: zephyr.trait_set.id,
          current_hp: 0,
          current_wounds: 0,
          resource_tracks: [ { key: burst_key, current: dexterity } ]
        }
      }
    }

    assert_redirected_to character_url(zephyr)
    assert_equal 0, zephyr.reload.trait_set.current_wounds, "Unyielding Resolve prevents the first Wound"
    assert_equal dexterity + 1, zephyr.trait_set.resource_tracks.sole.fetch("current"), "Kinetic Momentum still triggers on the ignored Wound"
    assert zephyr.character_revisions.exists?(event_type: "unyielding_resolve")
    assert_includes flash[:notice], "Wound-triggered abilities still triggered"

    patch tracker_character_url(zephyr), params: {
      character: {
        trait_set_attributes: {
          id: zephyr.trait_set.id,
          current_hp: 0,
          current_wounds: 0,
          resource_tracks: [ { key: burst_key, current: dexterity + 1 } ]
        }
      }
    }
    assert_equal dexterity + 1, zephyr.reload.trait_set.resource_tracks.sole.fetch("current"), "remaining at 0 HP is not a new Wound event"
    assert_equal 1, zephyr.character_revisions.where(event_type: "unyielding_resolve").count

    patch tracker_character_url(zephyr), params: {
      character: {
        trait_set_attributes: {
          id: zephyr.trait_set.id,
          current_hp: zephyr.trait_set.max_hp,
          current_wounds: 1,
          resource_tracks: [ { key: burst_key, current: dexterity + 1 } ]
        }
      }
    }
    assert_equal 1, zephyr.reload.trait_set.current_wounds, "the once-per-encounter protection does not prevent a second Wound"
    assert_equal dexterity + 2, zephyr.trait_set.resource_tracks.sole.fetch("current"), "each Wound gained adds another Burst, above the DEX Initiative amount"

    patch end_encounter_character_url(zephyr)
    assert_equal 0, zephyr.reload.trait_set.resource_tracks.sole.fetch("current")
    patch begin_encounter_character_url(zephyr)
    patch tracker_character_url(zephyr), params: {
      character: {
        trait_set_attributes: {
          id: zephyr.trait_set.id,
          current_wounds: 2,
          resource_tracks: [ { key: burst_key, current: dexterity } ]
        }
      }
    }
    assert_equal 1, zephyr.reload.trait_set.current_wounds
    assert_equal dexterity + 1, zephyr.trait_set.resource_tracks.sole.fetch("current"), "Unyielding Resolve resets for the next encounter and its ignored Wound still grants a Burst"
    assert_equal 2, zephyr.character_revisions.where(event_type: "unyielding_resolve").count
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "the sheet exposes an encounter end action that refreshes only encounter counters" do
    Rails.application.load_seed
    hunter = Character.create!(
      name: "Encounter Tracker",
      level: 2,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      ancestry: Ancestry.find_by!(name: "Gnome"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    hunter.trait_set.update!(resource_tracks: hunter.trait_set.resource_tracks.map { |track| track.merge("current" => 0) })

    get character_url(hunter)

    assert_response :success
    assert_select "form[action='#{end_encounter_character_path(hunter)}'] button[type='submit']", text: "End Encounter · refresh uses"

    patch end_encounter_character_url(hunter)

    assert_redirected_to character_url(hunter)
    assert_equal "Encounter ended. Encounter-reset counters were refreshed.", flash[:notice]
    tracks = hunter.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal 0, tracks.fetch("thrill_of_the_hunt").fetch("current")
    assert_equal 0, tracks.fetch("ancestry_gnome_optimistic").fetch("current")
    assert hunter.character_revisions.exists?(event_type: "encounter_end")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "owner can record Spellblade initiative mana only once until encounter end" do
    Rails.application.load_seed
    spellblade = Character.create!(
      name: "Initiative Button",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Commander"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced",
      stat_assignments: { strength: 2, dexterity: 1, intelligence: 1, will: 0 }
    )
    spellblade.update_columns(subclass_name: "Spellblade", status: "playable")
    stat_values = Character::STAT_NAMES.index_with { |stat| spellblade.stat_value(stat) }
    tracks = spellblade.derived_resource_tracks_for(stat_values:, level: 3, subclass_name: "Spellblade")
    spellblade.trait_set.update!(resource_tracks: tracks)
    spellblade.update_column(:level, 2)
    assert_empty spellblade.story_subclass_initiative_feature_entries
    assert_nil spellblade.initiative_resource_grant
    spellblade.update_column(:level, 3)

    get character_url(spellblade)
    assert_response :success
    assert_select ".progression-entry-subclass", /Firebrand.*Enchant Weapon for free/
    assert_select "input[name='initiative_roll[feature_actions][firebrand_enchant_weapon][used]'][type='checkbox']"
    assert_select "input[name='initiative_roll[feature_actions][firebrand_enchant_weapon][target]'][maxlength='80']"
    assert_select "form[action='#{begin_encounter_character_path(spellblade)}'] button[type='submit']", text: "Record Initiative Roll · gain 1 mana"

    patch begin_encounter_character_url(spellblade), params: {
      initiative_roll: { feature_actions: { firebrand_enchant_weapon: { used: "1" } } }
    }
    assert_redirected_to character_url(spellblade)
    assert_includes flash[:alert], "Name the weapon or wielder"
    assert_nil spellblade.reload.encounter_started_at
    assert_equal 0, spellblade.character_revisions.where(event_type: "initiative_roll").count

    patch begin_encounter_character_url(spellblade), params: {
      initiative_roll: { feature_actions: { firebrand_enchant_weapon: { used: "1", target: "Silver longsword" } } }
    }
    assert_redirected_to character_url(spellblade)
    assert_includes flash[:notice], "Initiative recorded. Initiative rolled; gained 1 Arcane Command mana"
    assert_includes flash[:notice], "Firebrand cast Enchant Weapon at Tier 2 for free on Silver longsword"
    assert_includes spellblade.character_revisions.where(event_type: "initiative_roll").sole.summary, "Heroes 2.0.1, p. 77"
    assert_equal 1, spellblade.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "spellblade_initiative_mana" }.fetch("current")

    get character_url(spellblade)
    assert_select "form[action='#{begin_encounter_character_path(spellblade)}']", count: 0
    assert_select ".field-hint", /Initiative recorded at/

    patch end_encounter_character_url(spellblade)
    assert_nil spellblade.reload.encounter_started_at
    assert_equal 0, spellblade.trait_set.resource_tracks.find { |track| track.fetch("key") == "spellblade_initiative_mana" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "Shadowpath records free Hunter's Mark and spends Ambusher advantage once per encounter" do
    Rails.application.load_seed
    hunter = Character.create!(
      name: "Ambusher Tracker",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    hunter.update_columns(subclass_name: "Shadowpath", status: "playable")
    stat_values = Character::STAT_NAMES.index_with { |stat| hunter.stat_value(stat) }
    tracks = hunter.derived_resource_tracks_for(stat_values:, level: 3, subclass_name: "Shadowpath")
    hunter.trait_set.update!(resource_tracks: tracks)

    patch game_feature_character_url(hunter), params: { game_feature: { action: "shadowpath_first_attack_advantage" } }
    assert_redirected_to character_url(hunter)
    assert_includes flash[:alert], "Record Initiative before spending Ambusher's first-attack advantage"
    assert_not hunter.character_revisions.exists?(event_type: "shadowpath_first_attack_advantage")

    get character_url(hunter)
    assert_response :success
    assert_select "input[name='initiative_roll[feature_actions][shadowpath_hunters_mark][used]'][type='checkbox']"
    assert_select "input[name='initiative_roll[feature_actions][shadowpath_hunters_mark][target]'][maxlength='160']"

    patch begin_encounter_character_url(hunter), params: {
      initiative_roll: { feature_actions: { shadowpath_hunters_mark: { used: "1" } } }
    }
    assert_redirected_to character_url(hunter)
    assert_includes flash[:alert], "Name the quarry or quarries"
    assert_nil hunter.reload.encounter_started_at

    patch begin_encounter_character_url(hunter), params: {
      initiative_roll: { feature_actions: { shadowpath_hunters_mark: { used: "1", target: "Ashen Stag" } } }
    }
    assert_redirected_to character_url(hunter)
    assert_includes flash[:notice], "Ambusher used Hunter's Mark for free on Ashen Stag"
    assert_includes flash[:notice], "Heroes 2.0.1, p. 28"
    assert_equal 1, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadowpath_first_attack_advantage" }.fetch("current")

    patch game_feature_character_url(hunter), params: { game_feature: { action: "shadowpath_first_attack_advantage" } }
    assert_redirected_to character_url(hunter)
    assert_includes flash[:notice], "Applied Ambusher's advantage to the first attack this encounter"
    assert_equal 0, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadowpath_first_attack_advantage" }.fetch("current")
    assert_includes hunter.character_revisions.where(event_type: "shadowpath_first_attack_advantage").sole.summary, "Heroes 2.0.1, p. 28"

    patch game_feature_character_url(hunter), params: { game_feature: { action: "shadowpath_first_attack_advantage" } }
    assert_redirected_to character_url(hunter)
    assert_includes flash[:alert], "already been used this encounter"
    assert_equal 1, hunter.character_revisions.where(event_type: "shadowpath_first_attack_advantage").count
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "Wild Heart automatically records Initiative and charge-gain movement triggers" do
    Rails.application.load_seed
    hunter = Character.create!(
      name: "High Ground Tracker",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    hunter.update_column(:subclass_name, "Wild Heart")
    stat_values = Character::STAT_NAMES.index_with { |stat| hunter.stat_value(stat) }
    hunter.trait_set.update!(resource_tracks: hunter.derived_resource_tracks_for(stat_values:, level: 3, subclass_name: "Wild Heart"))
    assert_equal 0, hunter.trait_set.resource_tracks.find { |track| track.fetch("key") == "thrill_of_the_hunt" }.fetch("current")
    assert_equal [ "I Have the High Ground" ], hunter.tracker_resource_event_grants_for([ { key: "thrill_of_the_hunt", current: 3 } ]).map { |grant| grant.fetch("feature_name") }

    tracker_params = lambda do |thrill:|
      {
        character: {
          trait_set_attributes: {
            id: hunter.trait_set.id,
            resource_tracks: [ { key: "thrill_of_the_hunt", current: thrill } ]
          }
        }
      }
    end
    patch tracker_character_url(hunter), params: tracker_params.call(thrill: 1)
    assert_redirected_to character_url(hunter)
    assert_nil flash[:alert], "tracker should save charge increases before Initiative"
    assert_includes flash[:notice], "one free movement after a gain of one or more Thrill of the Hunt charges"
    assert_equal 1, hunter.character_revisions.where(event_type: "wild_heart_high_ground_trigger").count

    get character_url(hunter)
    assert_response :success
    assert_select "input[name='initiative_roll[feature_actions][wild_heart_high_ground_initiative][used]']", count: 0
    assert_select "input[name='character[wild_heart_high_ground_movement_used]']", count: 0
    assert_select ".resource-event-guidance", text: /Saving an increased charge total automatically records this triggered free movement.*Heroes 2\.0\.1, p\. 29/

    patch begin_encounter_character_url(hunter)
    assert_redirected_to character_url(hunter)
    assert_includes flash[:notice], "I Have the High Ground triggered its free movement on Initiative"
    assert_includes flash[:notice], "Heroes 2.0.1, p. 29"
    assert_includes hunter.character_revisions.where(event_type: "initiative_roll").sole.summary, "ignoring difficult terrain"
    assert_equal [ "thrill_of_the_hunt" ], hunter.reload.trait_set.resource_tracks.map { |track| track.fetch("key") }

    get character_url(hunter)
    assert_select "input[name='character[wild_heart_high_ground_movement_used]']", count: 0
    assert_equal [ "I Have the High Ground" ], hunter.tracker_resource_event_grants_for([ { key: "thrill_of_the_hunt", current: 3 } ]).map { |grant| grant.fetch("feature_name") }
    patch tracker_character_url(hunter), params: tracker_params.call(thrill: 3)
    assert_redirected_to character_url(hunter)
    assert_nil flash[:alert], "tracker should save the submitted charge gain"
    assert_includes flash[:notice], "one free movement after a gain of one or more Thrill of the Hunt charges"
    assert_includes flash[:notice], "resolve up to half speed ignoring difficult terrain at the table"
    assert_includes flash[:notice], "Heroes 2.0.1, p. 29"
    assert_equal 3, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "thrill_of_the_hunt" }.fetch("current")
    assert_equal 2, hunter.character_revisions.where(event_type: "wild_heart_high_ground_trigger").count
    assert_includes hunter.character_revisions.where(event_type: "game_update").order(:created_at).last.summary, "Heroes 2.0.1, p. 29"

    patch tracker_character_url(hunter), params: tracker_params.call(thrill: 3)
    assert_equal "Game state saved.", flash[:notice], "an unchanged charge total does not retrigger the feature"
    assert_equal "In-game state updated", hunter.character_revisions.where(event_type: "game_update").order(:created_at).last.summary
    assert_equal 2, hunter.character_revisions.where(event_type: "wild_heart_high_ground_trigger").count

    patch tracker_character_url(hunter), params: tracker_params.call(thrill: 2)
    assert_equal "Game state saved.", flash[:notice], "spending a charge is not a gain event"
    assert_equal 2, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "thrill_of_the_hunt" }.fetch("current")
    patch tracker_character_url(hunter), params: tracker_params.call(thrill: 4)
    assert_includes flash[:notice], "one free movement after a gain of one or more Thrill of the Hunt charges"
    assert_equal 4, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "thrill_of_the_hunt" }.fetch("current")
    assert_equal 3, hunter.character_revisions.where(event_type: "wild_heart_high_ground_trigger").count

    patch end_encounter_character_url(hunter)
    assert_equal 0, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "thrill_of_the_hunt" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-02:AC-4 S-09:AC-3
  test "tracker resource guidance follows catalog text and unlock eligibility" do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Hunter")
    hunter = Character.create!(
      name: "Catalog Guidance Hero",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    hunter.update_column(:subclass_name, "Wild Heart")
    stat_values = Character::STAT_NAMES.index_with { |stat| hunter.stat_value(stat) }
    hunter.trait_set.update!(resource_tracks: hunter.derived_resource_tracks_for(stat_values:, level: 3, subclass_name: "Wild Heart"))

    catalog = Rules::NimbleCatalog.data
    original_resource_event_grants = catalog.fetch("resource_event_grants")
    changed_resource_event_grants = original_resource_event_grants.deep_dup
    changed_rule = changed_resource_event_grants.dig("resource_increased", "Hunter")
      .select { |rule| rule.fetch("feature_name") == "I Have the High Ground" }
      .sole
    changed_rule["minimum_level"] = 4
    changed_rule["tracker_note"] = "Test-defined tracker guidance."
    changed_rule["source_ref"] = "Test Rules, p. 99"
    catalog["resource_event_grants"] = changed_resource_event_grants

    begin
      get character_url(hunter)
      assert_response :success
      assert_select ".resource-event-guidance", { count: 0 }, "a level-4 catalog rule must not be shown to a level-3 character"

      changed_rule["minimum_level"] = 3
      get character_url(hunter)
      assert_response :success
      assert_select ".resource-event-guidance", { text: "Test-defined tracker guidance. Test Rules, p. 99.", count: 1 }
    ensure
      catalog["resource_event_grants"] = original_resource_event_grants
    end
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "the Initiative action shows and applies both class and subclass grants" do
    Rails.application.load_seed
    commander = Character.create!(
      name: "Combined Initiative",
      level: 4,
      character_class: CharacterClass.find_by!(name: "Commander"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: @background,
      stat_array: "balanced"
    )
    commander.update_column(:subclass_name, "Spellblade")
    stat_values = Character::STAT_NAMES.index_with { |stat| commander.stat_value(stat) }
    tracks = commander.derived_resource_tracks_for(stat_values:, level: 4, subclass_name: "Spellblade")
    commander.trait_set.update!(resource_tracks: tracks)

    get character_url(commander)

    assert_response :success
    assert_select ".safe-rest-action", /Fit for Any Battlefield/
    assert_select ".safe-rest-action", /Arcane Command/
    assert_select "form[action='#{begin_encounter_character_path(commander)}'] button[type='submit']", text: "Record Initiative Roll · apply listed features"

    patch begin_encounter_character_url(commander)

    assert_redirected_to character_url(commander)
    assert_includes flash[:notice], "gained #{commander.stat_value(:strength)} Combat Dice"
    assert_includes flash[:notice], "gained #{commander.stat_value(:intelligence)} Arcane Command mana"
    tracks = commander.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal commander.stat_value(:strength), tracks.fetch("combat_dice").fetch("current")
    assert_equal commander.stat_value(:intelligence), tracks.fetch("spellblade_initiative_mana").fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Commander sheet exposes Coordinated Strike uses and applies encounter-only initiative refunds" do
    Rails.application.load_seed
    commander = Character.create!(
      name: "Vanguard Resource Sheet",
      level: 11,
      character_class: CharacterClass.find_by!(name: "Commander"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced",
      stat_assignments: { strength: 2, dexterity: 1, intelligence: 1, will: 0 }
    )
    commander.update_columns(status: "playable", subclass_name: "Champion of the Vanguard")
    stat_values = Character::STAT_NAMES.index_with { |stat| commander.stat_value(stat) }
    tracks = commander.derived_resource_tracks_for(stat_values:, level: 11, subclass_name: "Champion of the Vanguard")
    max_strikes = tracks.find { |track| track.fetch("key") == "coordinated_strike_uses" }.fetch("max")
    tracks = tracks.map do |track|
      track.fetch("key") == "coordinated_strike_uses" ? track.merge("current" => max_strikes - 2) : track
    end
    commander.trait_set.update!(resource_tracks: tracks)

    get character_url(commander)

    assert_response :success
    assert_select ".resource-summary-item", /Coordinated Strike uses/
    assert_select ".resource-summary-item", /Coordinated Strike · Initiative refund/
    assert_select ".resource-rule-note summary", /Heroes 2\.0\.1, p\. 22/
    assert_select ".safe-rest-action", /Master Commander/
    assert_select ".safe-rest-action", /Survey the Battlefield/

    patch begin_encounter_character_url(commander)

    assert_redirected_to character_url(commander)
    assert_includes flash[:notice], "regained 1 temporary Coordinated Strike use"
    assert_includes flash[:notice], "regained 1 temporary Coordinated Strike use from Survey"
    tracks = commander.reload.trait_set.resource_tracks.index_by { |track| track.fetch("key") }
    assert_equal 2, tracks.fetch("coordinated_strike_initiative_uses").fetch("current")
    assert_equal max_strikes - 2, tracks.fetch("coordinated_strike_uses").fetch("current")

    patch end_encounter_character_url(commander)
    assert_equal 0, commander.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "coordinated_strike_initiative_uses" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Shepherd Initiative UI grants Light Bearer only when that Sacred Grace is recorded" do
    Rails.application.load_seed
    shepherd = Character.create!(
      name: "Light Bearer Initiative Sheet",
      level: 5,
      character_class: CharacterClass.find_by!(name: "Shepherd"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced",
      feature_choices: { "Sacred Grace" => { "5" => [ "Light Bearer", "Assist Me, My Friend!" ] } }
    )
    tracks = shepherd.trait_set.resource_tracks.map do |track|
      track.fetch("key") == "searing_light" ? track.merge("current" => track.fetch("max").to_i - 1) : track
    end
    shepherd.trait_set.update!(resource_tracks: tracks)
    unchosen = Character.create!(
      name: "Unchosen Shepherd Sheet",
      level: 5,
      character_class: CharacterClass.find_by!(name: "Shepherd"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )

    get character_url(unchosen)
    assert_response :success
    assert_select ".safe-rest-action", text: /Light Bearer/, count: 0

    get character_url(shepherd)
    assert_response :success
    assert_select ".safe-rest-action", /Light Bearer/
    assert_select "form[action='#{begin_encounter_character_path(shepherd)}'] button[type='submit']", text: "Record Initiative Roll · regain 1 Searing Light use"

    patch begin_encounter_character_url(shepherd)

    assert_redirected_to character_url(shepherd)
    assert_includes flash[:notice], "regained 1 temporary Searing Light use from Light Bearer"
    assert_equal 1, shepherd.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "searing_light_initiative_uses" }.fetch("current")
    assert_equal shepherd.stat_value(:will) - 1, shepherd.trait_set.resource_tracks.find { |track| track.fetch("key") == "searing_light" }.fetch("current")

    patch end_encounter_character_url(shepherd)
    assert_equal 0, shepherd.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "searing_light_initiative_uses" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-3
  test "Mage Initiative asks for real Elemental Surge dice and records legal Steel Will rerolls" do
    Rails.application.load_seed
    mage = Character.create!(
      name: "Elemental Surge Sheet",
      level: 17,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    mage.update_columns(status: "playable", subclass_name: "Control")
    stat_values = Character::STAT_NAMES.index_with { |stat| mage.stat_value(stat) }
    tracks = mage.derived_resource_tracks_for(stat_values:, level: 17, subclass_name: "Control")
    mage.trait_set.update!(resource_tracks: tracks)
    surge = tracks.find { |track| track.fetch("key") == "elemental_surge_mana" }

    get character_url(mage)

    assert_response :success
    assert_select "input[name='initiative_roll[dice_rolls][]'][type='number'][min='1'][max='4'][required]", count: 2
    assert_select "input[name='initiative_roll[rerolls][]'][type='number'][min='1'][max='4']", count: 2
    assert_select ".field-hint", /reroll each 1 once|reroll it once|cannot be rerolled again/i

    patch begin_encounter_character_url(mage), params: { initiative_roll: { dice_rolls: [ "3" ] } }
    assert_redirected_to character_url(mage)
    assert_includes flash[:alert], "Enter exactly 2 die results"
    assert_nil mage.reload.encounter_started_at
    assert_equal surge.fetch("current"), mage.trait_set.resource_tracks.find { |track| track.fetch("key") == "elemental_surge_mana" }.fetch("current")
    assert_equal 0, mage.character_revisions.where(event_type: "initiative_roll").count

    patch begin_encounter_character_url(mage), params: { initiative_roll: { dice_rolls: [ "1", "5" ], rerolls: [ "4", "" ] } }
    assert_redirected_to character_url(mage)
    assert_includes flash[:alert], "die results must each be between 1 and 4"
    assert_nil mage.reload.encounter_started_at

    patch begin_encounter_character_url(mage), params: { initiative_roll: { dice_rolls: [ "1", "3" ], rerolls: [ "4", "" ] } }
    assert_redirected_to character_url(mage)
    assert_includes flash[:notice], "regained #{mage.stat_value(:will) + 7} temporary mana"
    assert_includes flash[:notice], "d4 results: 1 → 4, 3 (Steel Will)"
    assert mage.reload.encounter_started_at.present?
    assert_equal mage.stat_value(:will) + 7, mage.trait_set.resource_tracks.find { |track| track.fetch("key") == "elemental_surge_mana" }.fetch("current")

    patch end_encounter_character_url(mage)
    assert_equal 0, mage.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "elemental_surge_mana" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-08:AC-4 S-09:AC-3
  test "Reaver sheet renders and tracks Bonescythe summon and shatter actions" do
    Rails.application.load_seed
    reaver = Character.create!(
      name: "Bonescythe Tracker",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Shadowmancer"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced",
      stat_assignments: { strength: 1, dexterity: 2, intelligence: 1, will: 0 },
      language_choices: [ "Elvish" ]
    )
    reaver.update_columns(level: 3, status: "playable", subclass_name: "Reaver")
    stat_values = Character::STAT_NAMES.index_with { |stat| reaver.stat_value(stat) }
    tracks = reaver.derived_resource_tracks_for(stat_values:, level: 3, subclass_name: "Reaver")
    reaver.trait_set.update!(resource_tracks: tracks, current_actions: 3)
    reaver.spells << Spell.find_by!(name: "Shadow Trap")

    tracks_with_minion = tracks.map do |track|
      track.fetch("key") == "shadow_minions" ? track.merge("current" => track.fetch("max")) : track
    end
    reaver.trait_set.update!(resource_tracks: tracks_with_minion)
    reaver.update_column(:level, 2)
    get character_url(reaver)
    assert_response :success
    assert_select "form[action='#{game_feature_character_path(reaver)}'] button[type='submit']", text: /Martyr Spawn/, count: 0
    assert_select "form[action='#{game_feature_character_path(reaver)}'] input[name='game_feature[action]'][value='shadow_exploit']", count: 0
    assert_select "form[action='#{game_feature_character_path(reaver)}'] input[name='game_feature[action]'][value='my_blood_my_power']", count: 0

    reaver.update_column(:level, 3)
    get character_url(reaver)
    assert_select "form[action='#{game_feature_character_path(reaver)}'] button[type='submit']", text: /Martyr Spawn/
    assert_select "form[action='#{game_feature_character_path(reaver)}'] input[name='game_feature[action]'][value='shadow_exploit']"
    assert_select "form[action='#{game_feature_character_path(reaver)}'] input[name='game_feature[action]'][value='my_blood_my_power']", count: 0

    reaver.trait_set.update!(resource_tracks: tracks, current_actions: 3)

    get character_url(reaver)
    assert_response :success
    assert_select ".progression-entry-subclass", /Bonescythe · 2d12/
    assert_select ".safe-rest-action .field-hint", /Any Invocations affecting Shadow Blast affect your Bonescythe instead.*Heroes 2\.0\.1, p\. 78/
    assert_select "form[action='#{begin_encounter_character_path(reaver)}']", count: 0
    assert_select "form[action='#{game_feature_character_path(reaver)}'] button[type='submit']", text: "Summon Bonescythe · spend 1 action"

    catalog_weapon_rules = Rules::NimbleCatalog.data.dig("story_subclass_weapon_rules", "Shadowmancer", "Reaver")
    original_weapon_rules = catalog_weapon_rules.fetch("Bonescythe")
    catalog_summon_rule = Rules::NimbleCatalog.class_resource_pool_for("Shadowmancer", "shadow_minions")
    original_summon_rule = catalog_summon_rule.dup
    catalog_weapon_rules["Bonescythe"] = original_weapon_rules.merge(
      "base_damage_dice" => 4,
      "additional_dice_per_interval" => 2,
      "additional_die_every_levels" => 2,
      "action_cost" => 2
    )
    catalog_summon_rule["summon_action_cost"] = 2

    begin
      get character_url(reaver)
      assert_response :success
      assert_select ".progression-entry-subclass", /Bonescythe · 6d12/
      assert_select ".progression-entry-subclass small", /\+2 damage dice every 2 levels/
      assert_select "form[action='#{game_feature_character_path(reaver)}'] button[type='submit']", text: "Summon Bonescythe · spend 2 actions"
      assert_select "form[action='#{game_feature_character_path(reaver)}'] button[type='submit']", text: "Summon Shadow Minion · spend 2 actions"
    ensure
      catalog_weapon_rules["Bonescythe"] = original_weapon_rules
      catalog_summon_rule.replace(original_summon_rule)
    end

    patch game_feature_character_url(reaver), params: { game_feature: { action: "summon_bonescythe" } }
    assert_redirected_to character_url(reaver)
    assert_equal 2, reaver.reload.trait_set.current_actions
    assert reaver.bonescythe_summoned?

    get character_url(reaver)
    assert_select "form[action='#{game_feature_character_path(reaver)}'] button[type='submit']", text: "Record Bonescythe Hit · shatter"
    patch game_feature_character_url(reaver), params: { game_feature: { action: "mark_bonescythe_hit" } }
    assert_redirected_to character_url(reaver)
    assert_not reaver.reload.bonescythe_summoned?

    reaver.update_column(:level, 7)
    patch game_feature_character_url(reaver), params: { game_feature: { action: "summon_bonescythe" } }
    assert_equal 1, reaver.reload.trait_set.current_actions
    get character_url(reaver)
    assert_select ".field-hint", /Grim Harrow: When striking with the Bonescythe, divide its damage dice among any number of adjacent targets within Reach/
    assert_select "form[action='#{game_feature_character_path(reaver)}'] button[type='submit']", text: "Record Critical Hit · shatter + Reap"
    assert_select "form[action='#{game_feature_character_path(reaver)}'] button[type='submit']", text: "Record Kill · shatter + Reap"
    assert_select "form[action='#{game_feature_character_path(reaver)}'] input[name='game_feature[action]'][value='my_blood_my_power']", count: 0
    assert_empty css_select(".field-hint").select { |hint| hint.text.include?("Otherworldly Might") }

    patch game_feature_character_url(reaver), params: { game_feature: { action: "mark_bonescythe_hit", outcome: "critical" } }
    assert_redirected_to character_url(reaver)
    assert_includes flash[:notice], "Reap summoned a Shadow Minion"
    assert_equal 1, reaver.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")

    patch game_feature_character_url(reaver), params: { game_feature: { action: "summon_bonescythe" } }
    assert_equal 0, reaver.reload.trait_set.current_actions
    patch game_feature_character_url(reaver), params: { game_feature: { action: "mark_bonescythe_hit", outcome: "kill" } }
    assert_redirected_to character_url(reaver)
    assert_includes flash[:notice], "Reap could not add a minion because you are at your limit"
    assert_equal 1, reaver.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")

    reaver.update_column(:level, 11)
    get character_url(reaver)
    assert_response :success
    assert_select ".field-hint", /Otherworldly Might: Gain advantage on concentration checks while you have any shadow minions/
    assert_select "form[action='#{game_feature_character_path(reaver)}'] input[name='game_feature[action]'][value='my_blood_my_power']"
    assert_select "select[name='game_feature[spell_name]'] option[value='Shadow Trap']"
    assert_select "select[name='game_feature[spell_name]'] option[value='Shadow Blast']", count: 0

    tracks_without_minions = reaver.trait_set.resource_tracks.map do |track|
      track.fetch("key") == "shadow_minions" ? track.merge("current" => 0) : track
    end
    reaver.trait_set.update!(resource_tracks: tracks_without_minions)
    get character_url(reaver)
    assert_empty css_select(".field-hint").select { |hint| hint.text.include?("Otherworldly Might") }
    reaver.trait_set.update!(resource_tracks: reaver.trait_set.resource_tracks.map do |track|
      track.fetch("key") == "shadow_minions" ? track.merge("current" => 1) : track
    end)

    patch game_feature_character_url(reaver), params: { game_feature: { action: "my_blood_my_power", spell_name: "Shadow Trap" } }
    assert_redirected_to character_url(reaver)
    assert_equal 1, reaver.reload.trait_set.current_wounds
    assert reaver.character_revisions.exists?(event_type: "my_blood_my_power")

    reaver.update_column(:level, 15)
    stats = Character::STAT_NAMES.index_with { |stat| reaver.stat_value(stat) }
    tracks = reaver.derived_resource_tracks_for(stat_values: stats, level: 15, subclass_name: "Reaver")
    tracks = tracks.map { |track| track.merge("current" => 0) }
    reaver.trait_set.update!(resource_tracks: tracks)

    get character_url(reaver)
    assert_select "form[action='#{begin_encounter_character_path(reaver)}'] button[type='submit']", text: "Record Initiative Roll · summon up to 2 minions"

    expected_gain = [ 2, tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("max") ].min
    patch begin_encounter_character_url(reaver)
    assert_redirected_to character_url(reaver)
    assert_includes flash[:notice], "summoned #{expected_gain} free Shadow Minions"
    assert_equal expected_gain, reaver.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadow_minions" }.fetch("current")
  end

  test "should track a keyed class resource and reject a value above its maximum" do
    Rails.application.load_seed
    mage = Character.create!(
      name: "Tracked Mage",
      level: 2,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      skill_set_attributes: { arcana: 7 }
    )
    patch tracker_character_url(mage), params: {
      character: {
        trait_set_attributes: {
          id: mage.trait_set.id,
          resource_tracks: [ { key: "mana", current: 3 } ]
        }
      }
    }

    assert_redirected_to character_url(mage)
    assert_equal 3, mage.reload.trait_set.resource_tracks.first.fetch("current")

    patch tracker_character_url(mage), params: {
      character: {
        trait_set_attributes: {
          id: mage.trait_set.id,
          resource_tracks: [ { key: "mana", current: 9 } ]
        }
      }
    }

    assert_redirected_to character_url(mage)
    assert_includes flash[:alert], "could not be saved"
    assert_equal 3, mage.reload.trait_set.resource_tracks.first.fetch("current")
  end

  test "should track a source-defined ancestry ability use within its limit" do
    Rails.application.load_seed
    halfling = Character.create!(
      name: "Tracked Halfling",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Halfling"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    track_key = "ancestry_halfling_elusive"

    patch tracker_character_url(halfling), params: {
      character: {
        trait_set_attributes: {
          id: halfling.trait_set.id,
          resource_tracks: [ { key: track_key, current: 0 } ]
        }
      }
    }

    assert_redirected_to character_url(halfling)
    assert_equal 0, halfling.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == track_key }.fetch("current")

    patch tracker_character_url(halfling), params: {
      character: {
        trait_set_attributes: {
          id: halfling.trait_set.id,
          resource_tracks: [ { key: track_key, current: 2 } ]
        }
      }
    }

    assert_includes flash[:alert], "could not be saved"
    assert_equal 0, halfling.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == track_key }.fetch("current")
  end

  test "gaining a Wound refreshes Dragonborn's source-defined bonus damage use" do
    Rails.application.load_seed
    dragonborn = Character.create!(
      name: "Wounded Dragonborn",
      level: 2,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Dragonborn"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    key = "ancestry_dragonborn_draconic_heritage"
    tracks = dragonborn.trait_set.resource_tracks.map do |track|
      track.fetch("key") == key ? track.merge("current" => 0) : track
    end
    dragonborn.trait_set.update!(resource_tracks: tracks)

    patch tracker_character_url(dragonborn), params: {
      character: {
        trait_set_attributes: {
          id: dragonborn.trait_set.id,
          current_wounds: 1
        }
      }
    }

    assert_redirected_to character_url(dragonborn)
    assert_equal 1, dragonborn.reload.trait_set.current_wounds
    assert_equal 1, dragonborn.trait_set.resource_tracks.find { |track| track.fetch("key") == key }.fetch("current")
    assert_equal 1, dragonborn.trait_set.current_resource
  end

  test "healing to full refreshes a Gnome's source-defined ally reroll" do
    Rails.application.load_seed
    gnome = Character.create!(
      name: "Healed Gnome",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Gnome"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    key = "ancestry_gnome_optimistic"
    tracks = gnome.trait_set.resource_tracks.map do |track|
      track.fetch("key") == key ? track.merge("current" => 0) : track
    end
    gnome.trait_set.update!(current_hp: gnome.trait_set.max_hp - 2, resource_tracks: tracks)

    patch tracker_character_url(gnome), params: {
      character: {
        trait_set_attributes: {
          id: gnome.trait_set.id,
          current_hp: gnome.trait_set.max_hp
        }
      }
    }

    assert_redirected_to character_url(gnome)
    refreshed_track = gnome.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == key }
    assert_equal 1, refreshed_track.fetch("current")
  end

  test "field rest rejects spending unavailable Hit Dice with a source explanation" do
    Rails.application.load_seed
    mage = Character.create!(
      name: "Careful Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "balanced"
    )
    original_hit_dice = mage.trait_set.current_hit_dice
    original_hp = mage.trait_set.current_hp
    original_revisions = mage.character_revisions.count

    patch field_rest_character_url(mage), params: {
      field_rest: { mode: "catch_breath", hit_dice: original_hit_dice + 1, die_rolls: "6, 6" }
    }

    assert_redirected_to character_url(mage)
    assert_includes flash[:alert], "Hit Dice available"
    assert_includes flash[:alert], "Core Rules 2.0.1, p. 16"
    assert_equal original_hit_dice, mage.reload.trait_set.current_hit_dice
    assert_equal original_hp, mage.trait_set.current_hp
    assert_equal original_revisions, mage.character_revisions.count
  end

  # S-02:AC-1 S-02:AC-2 S-07:AC-2 S-09:AC-1 S-09:AC-3
  test "the sheet offers and records Epic Mana as an explicit Field Rest healing replacement" do
    Rails.application.load_seed
    mage = Character.create!(
      name: "Epic Mana Rest",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: @background,
      stat_array: "balanced",
      feature_choices: { "Epic Boon" => [ "Epic Mana" ] }
    )
    mage.update_columns(level: 19, status: "playable")
    stats = mage.stat_set.attributes.slice("strength", "dexterity", "intelligence", "will").transform_values(&:to_i)
    tracks = mage.derived_resource_tracks_for(stat_values: stats, level: 19)
    mana = tracks.find { |track| track.fetch("key") == "mana" }
    tracks = tracks.map { |track| track.fetch("key") == "mana" ? track.merge("current" => 0) : track }
    mage.trait_set.update!(
      current_hp: 0,
      current_hit_dice: 1,
      max_hit_dice: 19,
      current_mana: 0,
      max_mana: mana.fetch("max"),
      resource_tracks: tracks
    )
    healing = mage.hit_die_sides + mage.stat_value("will")

    get character_url(mage)

    assert_response :success
    assert_select "input[name='field_rest[convert_healing_to_mana]'][type='checkbox'][value='1']", 2
    assert_select ".epic-mana-help", /Gamemaster's Guide 2\.0, p\. 23/

    patch field_rest_character_url(mage), params: {
      field_rest: {
        mode: "catch_breath",
        hit_dice: 1,
        die_rolls: mage.hit_die_sides.to_s,
        convert_healing_to_mana: "1"
      }
    }

    assert_redirected_to character_url(mage)
    assert_includes flash[:notice], "Converted #{healing} HP of healing into #{healing / 5} Mana with Epic Mana."
    assert_equal 0, mage.reload.trait_set.current_hp
    assert_equal healing / 5, mage.trait_set.current_mana
    assert_equal 0, mage.trait_set.current_hit_dice
    assert_includes mage.character_revisions.where(event_type: "field_rest").sole.summary, "Gamemaster's Guide 2.0, p. 23"
  end

  test "should reject impossible tracker state without changing derived limits" do
    @character.update!(character_class: @character_class)
    original_hp = @character.trait_set.current_hp
    original_max_hp = @character.trait_set.max_hp
    original_revision_count = @character.character_revisions.where(event_type: "game_update").count

    patch tracker_character_url(@character), params: {
      character: {
        conditions: "Should not persist",
        trait_set_attributes: {
          id: @character.trait_set.id,
          current_hp: original_max_hp + 1,
          current_wounds: -1,
          max_hp: 999,
          armor: 999
        }
      }
    }

    assert_redirected_to character_url(@character)
    assert_includes flash[:alert], "could not be saved"
    @character.reload
    assert_equal original_hp, @character.trait_set.current_hp
    assert_equal original_max_hp, @character.trait_set.max_hp
    assert_equal 0, @character.trait_set.armor
    assert_equal original_revision_count, @character.character_revisions.where(event_type: "game_update").count
  end

  private
    def canonical_character_attributes
      {
        description: "Ready for the road.",
        character_class_id: @character_class.id,
        ancestry_id: @ancestry.id,
        background_id: @background.id,
        stat_array: "balanced",
        level: 1,
        language_choices: [ "Draconic" ],
        skill_set_attributes: { might: 7 }
      }
    end
end
