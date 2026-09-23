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
    assert_selector "[data-character-builder-target='savesPreview']", text: "STR+ / INT−"
    find("select[name='character[stat_assignments][strength]'] option[value='0']").select_option
    find("select[name='character[stat_assignments][intelligence]'] option[value='1']").select_option
    find("select[name='character[stat_assignments][will]'] option[value='2']").select_option
    assert_selector "[data-character-builder-target='saveDcPreview']", text: "11"
    fill_in "character_skill_set_attributes_might", with: 5

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

  test "the guided builder previews structured skill and language grants" do
    visit new_character_url

    select "Mage", from: "Class"
    select "Orc", from: "Ancestry"
    select "Raised by Goblins", from: "Background"
    select "Balanced", from: "Stat array"

    assert_selector "[data-skill-base='might']", text: "base +2"
    assert_selector "[data-character-builder-target='languagesPreview']", text: "Common, Goblin"
    assert_selector "[data-character-builder-target='armorPreview']", text: "2"
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-1 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "the builder previews and saves the level-scaled starting-gold option" do
    visit new_character_url

    fill_in "Character name", with: "Gold Start Hero"
    fill_in "Level", with: 3
    select "Mage", from: "Class"
    select "Human", from: "Ancestry"
    select "Fearless", from: "Background"
    select "Balanced", from: "Stat array"
    assert_selector "[data-character-builder-target='armorPreview']", text: "1"
    assert_selector "[data-character-builder-target='backgroundEquipmentNote']", visible: true
    select "Starting gold instead (50 gp per level)", from: "Starting equipment"

    assert_selector "[data-character-builder-target='startingEquipmentPreview']", text: "150 gp"
    assert_selector "[data-character-builder-target='armorPreview']", text: "-1"
    assert_no_selector "[data-character-builder-target='backgroundEquipmentNote']", visible: true
    assert_text "Core Rules 2.0.1, pp. 20, 33; Heroes 2.0.1, p. 67"
    assert_text "class-appropriate unarmored Armor, including Zephyr’s DEX + STR"
    click_on "Save draft"

    assert_text "Draft saved"
    assert_text "150 gp"
    character = Character.find_by!(name: "Gold Start Hero")
    assert_equal 150, character.current_gold
    assert_equal 1, character.inventory_slots_used

    fill_in "Gold (gp)", with: 501
    click_on "Save game state"

    assert_text "Game state saved."
    character.reload
    assert_equal 501, character.current_gold
    assert_equal 2, character.inventory_slots_used
    assert_text "2 / #{character.inventory_slots_capacity} slots used"
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "the builder previews starting shield Armor and removes it for a gold start" do
    visit new_character_url

    fill_in "Character name", with: "Buckler Preview Hero"
    select "Oathsworn", from: "Class"
    select "Human", from: "Ancestry"
    select "Fearless", from: "Background"
    select "Balanced", from: "Stat array"

    assert_selector "[data-character-builder-target='armorPreview']", text: "8"
    select "Starting gold instead (50 gp per level)", from: "Starting equipment"
    assert_selector "[data-character-builder-target='armorPreview']", text: "0"

    click_on "Save draft"

    assert_text "Draft saved"
    assert_text "Starting gold replaces the class/background gear package"
    armor_card = find(".vital-card", text: "Unarmored DEX + origin")
    assert_equal "0", armor_card.find("strong").text
    assert_text "Core Rules 2.0.1, p. 33"
  end

  test "choosing Academy Dropout reveals its Utility Spell picker" do
    visit new_character_url

    select "Academy Dropout", from: "Background"
    assert_selector "[data-character-builder-target='backgroundSpellChoiceField']", visible: true
    select "Wind · Wind Whisper", from: "Academy Dropout · Utility Spell"

    assert_equal "Wind Whisper", find("select[name='character[spell_choices][Academy Dropout][1]']").value
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

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-07:AC-2 S-09:AC-1 S-09:AC-3
  test "the sheet explains and tracks a limited-use ancestry ability" do
    character = Character.create!(
      name: "Lucky Sheet Hero",
      character_class: @character_class,
      ancestry: Ancestry.find_by!(name: "Halfling"),
      background: @background,
      stat_array: "balanced"
    )

    visit character_url(character)

    assert_text "Elusive · save success"
    assert_text "Core Rules 2.0.1, p. 23"
    find(".resource-rule-note summary").click
    assert_text "If you fail a save, you can succeed instead, 1/Safe Rest."
    find("label", text: /Elusive · save success/).find("input[type='number']").set(0)
    click_on "Save game state"

    assert_text "Game state saved"
    assert_equal 0, character.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "ancestry_halfling_elusive" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "the sheet completes a source-backed Safe Rest" do
    character = Character.create!(
      name: "Resting Sheet Hero",
      level: 2,
      character_class: CharacterClass.find_by!(name: "Oathsworn"),
      ancestry: Ancestry.find_by!(name: "Dragonborn"),
      background: @background,
      stat_array: "balanced"
    )
    character.trait_set.update!(
      current_hp: 1,
      current_hit_dice: 0,
      current_wounds: 2,
      temp_hp: 4,
      resource_tracks: character.trait_set.resource_tracks.map { |track| track.merge("current" => 0) }
    )

    visit character_url(character)

    assert_text "At a GM-designated safe location"
    assert_text "Core Rules 2.0.1, pp. 9, 16"
    click_on "Complete Safe Rest"

    assert_text "Safe Rest completed. HP, Hit Dice, and tracked resources were refreshed."
    assert_text "Safe Rest"
    character.reload
    assert_equal character.trait_set.max_hp, character.trait_set.current_hp
    assert_equal character.trait_set.max_hit_dice, character.trait_set.current_hit_dice
    assert_equal 1, character.trait_set.current_wounds
    assert_equal 0, character.trait_set.temp_hp
    assert_equal 1, character.trait_set.resource_tracks.find { |track| track.fetch("key") == "ancestry_dragonborn_draconic_heritage" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "the sheet resolves Catch Breath rolls and spends Hit Dice" do
    character = Character.create!(
      name: "Breathing Sheet Hero",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "standard",
      stat_assignments: { strength: -1, dexterity: 0, intelligence: 2, will: 2 }
    )
    character.trait_set.update!(current_hp: 2)

    visit character_url(character)

    assert_text "Core Rules 2.0.1, p. 16"
    fill_in "Single Hit Die roll (d6)", with: "6"
    click_on "Catch Breath · 10 min"

    assert_text "Catch Breath complete: recovered 5 HP."
    assert_text "Field Rest"
    assert_equal 7, character.reload.trait_set.current_hp
    assert_equal 0, character.trait_set.current_hit_dice
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "the sheet tracks item slots, flags over-capacity loads, and lets gear be edited" do
    visit character_url(@character)

    capacity = @character.reload.inventory_slots_capacity
    fill_in "Add item or stack", with: "Dragon Shield"
    fill_in "Slots used", with: capacity + 1
    click_on "Add item"

    assert_text "Dragon Shield"
    assert_text "Over capacity by 1 slot."
    item = @character.reload.inventory_items.find_by!(name: "Dragon Shield")
    row = find("[data-inventory-item-id='#{item.id}']")
    row.find("input[name$='[slots]']").set("2")
    within(row) { click_on "Save item" }

    assert_text "Inventory item updated."
    assert_text "2 / #{capacity} slots used"
    item.reload
    row = find("[data-inventory-item-id='#{item.id}']")
    accept_confirm("Remove Dragon Shield from inventory?") do
      within(row) { click_on "Remove" }
    end

    assert_text "Dragon Shield removed from inventory."
    assert_text "0 / #{capacity} slots used"
    assert_not InventoryItem.exists?(item.id)
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
