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
    assert_equal @character.stat_set.strength, payload.dig("stats", "strength")
    assert_equal @character.skill_set.might, payload.dig("skills", "might")
    assert_equal @character.trait_set.max_hp, payload.dig("traits", "max_hp")
    assert_equal [], payload.fetch("spells")
    assert_equal "Draft", payload.fetch("status_label")
  end

  test "should get edit" do
    get edit_character_url(@character)
    assert_response :success
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

  private
    def canonical_character_attributes
      {
        description: "Ready for the road.",
        character_class_id: @character_class.id,
        ancestry_id: @ancestry.id,
        background_id: @background.id,
        stat_array: "balanced",
        level: 1
      }
    end
end
