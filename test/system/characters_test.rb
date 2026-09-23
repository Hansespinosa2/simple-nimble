require "application_system_test_case"

class CharactersTest < ApplicationSystemTestCase
  # S-01:AC-1 S-01:AC-3 S-01:AC-4 S-05:AC-1 S-05:AC-2 S-05:AC-4 S-05:AC-5 S-09:AC-1 S-09:AC-3
  setup do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Berserker")
    @character_class = CharacterClass.find_by!(name: "Berserker")
    @ancestry = Ancestry.find_by!(name: "Human")
    @background = Background.find_by!(name: "Fearless")
    @character = Character.create!(
      name: "System Test Hero",
      description: "A brave adventurer seeking glory.",
      level: 1,
      legacy_background_text: "Soldier",
      race: "Human",
      nimble_class: "Warrior",
      languages: "Common, Elvish"
    )
  end

  test "visiting the index" do
    visit characters_url
    assert_selector "h1", text: "Your heroes"
  end

  test "should create character" do
    visit characters_url
    click_on "New character"

    fill_in "character_background", with: "Found beneath the old bridge"
    fill_in "character_description", with: @character.description
    fill_in "character_level", with: @character.level
    fill_in "character_name", with: "Browser Built Hero"
    click_on "Save draft"

    assert_text "Draft saved"
    assert_text "Browser Built Hero"
    assert_equal "Found beneath the old bridge", Character.find_by!(name: "Browser Built Hero").legacy_background_text
  end

  test "the guided builder previews derived values and finalizes a legal character" do
    visit new_character_url

    fill_in "character_name", with: "Preview Hero"
    select @character_class.name, from: "Class"
    select @ancestry.name, from: "Ancestry"
    select @background.name, from: "Background"
    select "Balanced", from: "Stat array"

    assert_selector "[data-character-builder-target='hpPreview']", text: @character_class.starting_hp.to_s
    assert_selector "[data-character-builder-target='previewNote']", text: "Changes are preview-only until you save."
    assert_selector "[data-stat-role='strength']", text: "Key Stat"
    assert_selector "[data-character-builder-target='speedPreview']", text: "6"
    fill_in "character_skill_set_attributes_might", with: 7

    click_on "Save and mark playable"

    assert_text "Character created and ready to play"
    assert_text "Preview Hero"
    assert_selector ".badge-playable"
    created = Character.find_by!(name: "Preview Hero")
    assert created.playable?
    assert_equal @character_class, created.character_class
    assert_equal @ancestry, created.ancestry
    assert_equal @background, created.background
  end

  test "the sheet tracks live game state and records the update" do
    visit character_url(@character)

    fill_in "character_trait_set_attributes_current_hp", with: 7
    fill_in "character_trait_set_attributes_temp_hp", with: 2
    fill_in "character_trait_set_attributes_current_wounds", with: 4
    fill_in "character_trait_set_attributes_current_actions", with: 1
    fill_in "character_trait_set_attributes_current_hit_dice", with: 0
    fill_in "character_conditions", with: "Smoldering"
    fill_in "character_inventory", with: "Torch, rope"
    fill_in "character_game_notes", with: "Met the ferryman."
    click_on "Save game state"

    assert_text "Game state saved"
    assert_text "Game update"
    assert_equal 7, @character.reload.trait_set.current_hp
    assert_equal 2, @character.trait_set.temp_hp
    assert_equal 4, @character.trait_set.current_wounds
    assert_equal 1, @character.trait_set.current_actions
    assert_equal 0, @character.trait_set.current_hit_dice
    assert_equal "Smoldering", @character.conditions
    assert_equal "Torch, rope", @character.inventory
    assert_equal "Met the ferryman.", @character.game_notes
  end

  test "should update Character" do
    visit character_url(@character)
    click_on "Edit sheet", match: :first

    fill_in "character_background", with: "Updated story"
    fill_in "character_description", with: @character.description
    fill_in "character_level", with: @character.level
    fill_in "character_name", with: "Updated Browser Hero"
    click_on "Save draft"

    assert_text "Character was successfully updated"
    assert_text "Updated Browser Hero"
    assert_equal "Updated Browser Hero", @character.reload.name
    assert_equal "Updated story", @character.legacy_background_text
  end

  test "should destroy Character" do
    visit character_url(@character)
    accept_confirm { click_on "Delete character", match: :first }

    assert_text "Your heroes"
    assert_not Character.exists?(@character.id)
  end
end
