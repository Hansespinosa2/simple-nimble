require "test_helper"

class CharactersControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed if Character.count.zero?
    @character = Character.create!(
      name: "Test Hero",
      description: "A brave adventurer seeking glory.",
      level: 1,
      background: "Soldier",
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
      post characters_url, params: { character: { background: @character.background, description: @character.description, languages: @character.languages, level: @character.level, name: @character.name, nimble_class: @character.nimble_class, race: @character.race } }
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
    patch character_url(@character), params: { character: { background: @character.background, description: @character.description, languages: @character.languages, level: @character.level, name: @character.name, nimble_class: @character.nimble_class, race: @character.race } }
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
end
