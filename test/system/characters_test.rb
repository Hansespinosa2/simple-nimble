require "application_system_test_case"

class CharactersTest < ApplicationSystemTestCase
  setup do
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

  test "visiting the index" do
    visit characters_url
    assert_selector "h1", text: "Characters"
  end

  test "should create character" do
    visit characters_url
    click_on "New character"

    fill_in "character_background", with: @character.background
    fill_in "character_description", with: @character.description
    fill_in "character_languages", with: @character.languages
    fill_in "character_level", with: @character.level
    fill_in "character_name", with: @character.name
    fill_in "character_nimble_class", with: @character.nimble_class
    fill_in "character_race", with: @character.race
    click_on "Create Character"

    assert_text "Character was successfully created"
    click_on "Back"
  end

  test "should update Character" do
    visit character_url(@character)
    click_on "Edit this character", match: :first

    fill_in "character_background", with: @character.background
    fill_in "character_description", with: @character.description
    fill_in "character_languages", with: @character.languages
    fill_in "character_level", with: @character.level
    fill_in "character_name", with: @character.name
    fill_in "character_nimble_class", with: @character.nimble_class
    fill_in "character_race", with: @character.race
    click_on "Update Character"

    assert_text "Character was successfully updated"
    click_on "Back"
  end

  test "should destroy Character" do
    visit character_url(@character)
    accept_confirm { click_on "Destroy this character", match: :first }

    assert_text "Character was successfully destroyed"
  end
end
