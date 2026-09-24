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
    assert_select "select[name='character[starting_equipment_choice]'] option[value='starting_gold']", text: "Starting gold instead (50 gp per level)"
    assert_select "select[name='character[stat_assignments][strength]']"
    assert_select "select[name='character[stat_assignments][will]']"
    assert_select "[data-character-builder-target='savesPreview']"
    assert_select "[data-character-builder-target='backgroundSpellChoiceField'][hidden]"
    assert_select "select[name='character[spell_choices][Academy Dropout][1]'] option[value='Firebrand']"
    rules_payload = JSON.parse(Nokogiri::HTML(response.body).at_css("form.builder-form")["data-character-builder-rules-value"])
    academy_background_id = Background.find_by!(name: "Academy Dropout").id.to_s
    assert_equal true, rules_payload.dig("backgrounds", academy_background_id, "starting_spell_choice")
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

  test "should explain the Academy Dropout Utility Spell requirement when missing" do
    post characters_url, params: {
      character: canonical_character_attributes.merge(
        name: "Missing Academy Spell Hero",
        background_id: Background.find_by!(name: "Academy Dropout").id
      ),
      finalize: "1"
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Academy Dropout requires one Utility Spell choice."
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
    assert_equal @character.trait_set.current_hp, entry.fetch("current_hp")
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
    assert_equal @character.trait_set.max_hp, payload.dig("traits", "max_hp")
    assert_equal [], payload.fetch("spells")
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
  test "should reject a direct level edit even when skill points are supplied" do
    character = Character.create!(canonical_character_attributes.merge(name: "No Shortcut Hero"))
    character.finalize_creation!
    original_revisions = character.character_revisions.count

    patch character_url(character), params: {
      character: {
        level: 2,
        skill_set_attributes: { id: character.skill_set.id, might: 8 }
      }
    }

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
    assert_select "form[action='#{begin_encounter_character_path(spellblade)}'] button[type='submit']", text: "Record Initiative Roll · gain 1 mana"

    patch begin_encounter_character_url(spellblade)
    assert_redirected_to character_url(spellblade)
    assert_equal "Initiative recorded. Initiative rolled; gained 1 Arcane Command mana.", flash[:notice]
    assert_equal 1, spellblade.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "spellblade_initiative_mana" }.fetch("current")

    get character_url(spellblade)
    assert_select "form[action='#{begin_encounter_character_path(spellblade)}']", count: 0
    assert_select ".field-hint", /Initiative recorded at/

    patch end_encounter_character_url(spellblade)
    assert_nil spellblade.reload.encounter_started_at
    assert_equal 0, spellblade.trait_set.resource_tracks.find { |track| track.fetch("key") == "spellblade_initiative_mana" }.fetch("current")
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
    assert_select "form[action='#{begin_encounter_character_path(reaver)}']", count: 0
    assert_select "form[action='#{game_feature_character_path(reaver)}'] button[type='submit']", text: "Summon Bonescythe · spend 1 action"

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
    assert_select "form[action='#{game_feature_character_path(reaver)}'] button[type='submit']", text: "Record Critical Hit · shatter + Reap"
    assert_select "form[action='#{game_feature_character_path(reaver)}'] button[type='submit']", text: "Record Kill · shatter + Reap"
    assert_select "form[action='#{game_feature_character_path(reaver)}'] input[name='game_feature[action]'][value='my_blood_my_power']", count: 0

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
    assert_select "form[action='#{game_feature_character_path(reaver)}'] input[name='game_feature[action]'][value='my_blood_my_power']"
    assert_select "select[name='game_feature[spell_name]'] option[value='Shadow Trap']"
    assert_select "select[name='game_feature[spell_name]'] option[value='Shadow Blast']", count: 0

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

  test "should reject impossible tracker state without changing derived limits" do
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
