require "test_helper"

# S-05:AC-1 S-05:AC-3 S-05:AC-4 S-05:AC-5 S-06:AC-6 S-09:AC-3
class CharactersControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed if Character.count.zero?
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
  end

  test "should get new" do
    get new_character_url
    assert_response :success
  end

  test "should create character" do
    assert_difference("Character.count") do
      post characters_url, params: { character: { legacy_background_text: @character.legacy_background_text, description: @character.description, languages: @character.languages, level: @character.level, name: @character.name, nimble_class: @character.nimble_class, race: @character.race } }
    end

    assert_redirected_to character_url(Character.last)
  end

  test "should show character" do
    get character_url(@character)
    assert_response :success
  end

  test "should get edit" do
    get edit_character_url(@character)
    assert_response :success
  end

  test "should update character" do
    patch character_url(@character), params: { character: { legacy_background_text: @character.legacy_background_text, description: @character.description, languages: @character.languages, level: @character.level, name: @character.name, nimble_class: @character.nimble_class, race: @character.race } }
    assert_redirected_to character_url(@character)
  end

  test "should destroy character" do
    assert_difference("Character.count", -1) do
      delete character_url(@character)
    end

    assert_redirected_to characters_url
  end

  test "should have stats and skills for each character" do
    Character.all.each do |character|
      puts character.name
      assert_not_nil character.stat_set
      assert_not_nil character.skill_set
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
    assert_equal "In-game state updated", @character.character_revisions.order(:id).last.summary
  end
end
