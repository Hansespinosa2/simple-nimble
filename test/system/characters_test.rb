require "application_system_test_case"

class CharactersTest < ApplicationSystemTestCase
  # S-01:AC-1 S-01:AC-3 S-01:AC-4 S-05:AC-1 S-05:AC-2 S-05:AC-4 S-05:AC-5 S-09:AC-1 S-09:AC-3
  setup do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Berserker")
    @account = create_account(display_name: "System Player", email: "system-#{SecureRandom.hex(4)}@example.com")
    visit new_session_path
    fill_in "email", with: @account.email
    fill_in "password", with: TEST_PASSWORD
    click_button "Sign in"
    @character_class = CharacterClass.find_by!(name: "Berserker")
    @ancestry = Ancestry.find_by!(name: "Human")
    @background = Background.find_by!(name: "Fearless")
    @character = Character.create!(
      account: @account,
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

  test "a player can register with a confirmed password and sign in" do
    click_button "Sign out"
    click_link "Create an account"

    fill_in "What should your table call you?", with: "New Browser Player"
    fill_in "Email", with: "browser-player-#{SecureRandom.hex(4)}@example.com"
    fill_in "Password", with: "a-long-browser-test-password"
    fill_in "Confirm password", with: "a-long-browser-test-password"
    click_button "Create account"

    assert_selector "h1", text: "Your heroes"
    assert_text "New Browser Player"
    new_account = Account.find_by!(display_name: "New Browser Player")
    assert new_account.authenticate("a-long-browser-test-password")
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

    assert_selector ".skill-rule-note", text: /explicitly grant.*Songweaver's Jack of All Trades.*Safe Rest.*Core Rules 2\.0\.1, p\. 21/
    assert_equal Character::MAX_LEVEL.to_s, find("#character_level")["max"]

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
    check "Elvish"
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
    assert_equal [ "Elvish" ], created.language_choices
    assert_equal 4, created.inventory_slots_used
    assert_text "Starting kit carried"
    assert_text "4 slots · included in total"
    assert_text "#{created.inventory_slots_used} / #{created.inventory_slots_capacity} slots used"
    battleaxe_item = created.inventory_items.find_by!(name: "Battleaxe")
    battleaxe = find("[data-inventory-item-id='#{battleaxe_item.id}']")
    assert_equal "2", battleaxe.find("input[name$='[slots]']").value
    assert_includes battleaxe.text, "Core Rules 2.0.1, pp. 21, 34"
  end

  # S-04:AC-6 S-09:AC-3
  test "a playable character locks its build but still saves identity and story edits" do
    character = Character.new(
      account: @account,
      name: "Locked Build Hero",
      character_class: @character_class,
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    character.valid?
    character.skill_set.might = character.skill_set.might.to_i + character.skill_point_budget
    stat_values = character.stat_set.attributes.slice(*Character::STAT_NAMES).transform_values(&:to_i)
    language_count = character.language_choice_count(stat_values)
    character.language_choices = character.language_choice_options_for(stat_values, excluding: []).first(language_count)
    character.save!
    character.finalize_creation!

    visit edit_character_url(character)

    assert_selector "select[name='character[character_class_id]'][disabled]"
    assert_selector "select[name='character[ancestry_id]'][disabled]"
    assert_selector "select[name='character[background_id]'][disabled]"
    assert_selector "select[name='character[stat_array]'][disabled]"
    Character::STAT_NAMES.each do |stat|
      assert_selector "select[name='character[stat_assignments][#{stat}]'][disabled]"
    end
    assert_selector "input[name='character[language_choices][]'][disabled]"
    assert_selector "input[name='character[skill_set_attributes][might]'][disabled]"
    assert_no_selector ".spell-picker"
    assert_selector ".spell-chips"
    assert_text "Rules and progression choices are locked to preserve this character's history."
    assert_no_button "Save and mark playable"
    assert_button "Save changes"

    fill_in "character_name", with: "Renamed Locked Build"
    fill_in "character_background", with: "A promise kept on the northern road."
    fill_in "character_description", with: "Still the same hero, with a new chapter."
    click_on "Save changes"

    assert_selector "h1", text: "Renamed Locked Build"
    assert_selector ".sheet-description", text: "Still the same hero, with a new chapter."
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2
  test "the builder previews an Oozeling's ancestry-upgraded Hit Die" do
    visit new_character_url

    select "Mage", from: "Class"
    select "Oozeling/Construct", from: "Ancestry"

    assert_selector "[data-character-builder-target='hitDiePreview']", text: "1d8"
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "the edit builder combines subclass Hit Die upgrades with ancestry advancement" do
    hunter = Character.create!(
      account: @account,
      name: "Wild Heart Oozeling",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      ancestry: Ancestry.find_by!(name: "Oozeling/Construct"),
      background: @background,
      stat_array: "balanced",
      subclass_name: "Wild Heart"
    )

    assert_equal "1d12", hunter.trait_set.hit_die
    visit edit_character_url(hunter)

    assert_selector "[data-character-builder-target='hitDiePreview']", text: "1d12"
    assert_text "Upgrade your Hit Dice to d10s."
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "the builder explains Elf Initiative advantage without treating it as a numeric bonus" do
    visit new_character_url

    select "Mage", from: "Class"
    select "Elf", from: "Ancestry"

    assert_selector "[data-character-builder-target='ancestryHint']", text: /Roll Initiative with advantage.*numeric Initiative bonus.*Core Rules 2\.0\.1, p\. 23/
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

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "the builder explains and previews Back Out of Retirement's Wound effects" do
    visit new_character_url

    select "Mage", from: "Class"
    select "Human", from: "Ancestry"
    select "Back Out of Retirement", from: "Background"
    select "Balanced", from: "Stat array"

    assert_selector "[data-character-builder-target='backgroundHint']", text: /At-table reminder \(not automatically resolved\): Take 1 Wound to use an ability or cast a spell as one level higher\. The sheet already applies Old Bones' −1 maximum Wounds\. \(Core Rules 2\.0\.1, p\. 28\)/
    assert_selector "[data-character-builder-target='woundsPreview']", text: "5"
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2
  test "the builder only offers Songweaver's source-defined other spell schools" do
    visit new_character_url
    select "Songweaver", from: "Class"

    assert_selector "[data-character-builder-target='spellSchoolChoiceField']", visible: true
    assert_selector "select[name='character[spell_school_choice]'] option", text: "Fire"
    assert_selector "select[name='character[spell_school_choice]'] option", text: "Wind", count: 0
    assert_text "You know cantrips from the Wind school and 1 other school of your choice."
    assert_text "Heroes 2.0.1, p. 55"
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-1 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "the builder previews and saves the level-scaled starting-gold option" do
    catalog = Rules::NimbleCatalog.data
    original_starting_equipment = catalog.fetch("starting_equipment")
    catalog["starting_equipment"] = original_starting_equipment.merge(
      "gold_per_level" => 75,
      "gold_per_level_source_quote" => "75 gp for starting equipment; multiply by starting level."
    )

    begin
      visit new_character_url

      fill_in "Character name", with: "Gold Start Hero"
      fill_in "Level", with: 3
      select "Mage", from: "Class"
      select "Human", from: "Ancestry"
      select "Fearless", from: "Background"
      select "Balanced", from: "Stat array"
      assert_selector "[data-character-builder-target='armorPreview']", text: "1"
      assert_selector "[data-character-builder-target='backgroundEquipmentNote']", visible: true
      select "Starting gold instead (75 gp per level)", from: "Starting equipment"

      assert_selector "[data-character-builder-target='startingEquipmentPreview']", text: "225 gp"
      assert_selector "[data-character-builder-target='armorPreview']", text: "-1"
      assert_no_selector "[data-character-builder-target='backgroundEquipmentNote']", visible: true
      assert_text "Core Rules 2.0.1, pp. 20, 32–33; Heroes 2.0.1, p. 67"
      assert_text "adding gear does not automatically deduct its cost from tracked gold"
      click_on "Save draft"

      assert_text "Draft saved"
      assert_text "225 gp"
      character = Character.find_by!(name: "Gold Start Hero")
      assert_equal 225, character.current_gold
      assert_equal 1, character.inventory_slots_used
      assert_no_text "Starting class gear"
      assert_text "Gold carried is counted above"

      fill_in "Gold (gp)", with: 501
      click_on "Save game state"

      assert_text "Game state saved."
      character.reload
      assert_equal 501, character.current_gold
      assert_equal 2, character.inventory_slots_used
      assert_text "2 / #{character.inventory_slots_capacity} slots used"
    ensure
      catalog["starting_equipment"] = original_starting_equipment
    end
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2
  test "the builder reports when starting-gold rules are unavailable" do
    catalog = Rules::NimbleCatalog.data
    original_starting_equipment = catalog.fetch("starting_equipment")
    catalog["starting_equipment"] = original_starting_equipment.merge("gold_per_level" => nil)

    begin
      visit new_character_url

      find("[data-character-builder-target='startingEquipmentChoice'] option[value='starting_gold']").select_option

      assert_selector "[data-character-builder-target='startingEquipmentPreview']", text: "Starting gold rules unavailable"
    ensure
      catalog["starting_equipment"] = original_starting_equipment
    end
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
    find("summary", text: /Slot rules/).click
    assert_text "Optional Deflect"
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "the live preview doubles Zephyr's unarmored Armor at level thirteen" do
    visit new_character_url

    select "Zephyr", from: "Class"
    select "Human", from: "Ancestry"
    select "Fearless", from: "Background"
    select "Standard", from: "Stat array"
    assert_selector "[data-character-builder-target='armorPreview']", text: "3"

    fill_in "Level", with: "13"
    rules_payload = JSON.parse(find("form.builder-form")["data-character-builder-rules-value"])
    zephyr_id = find("select[name='character[character_class_id]']").value
    assert_equal "13", find("#character_level").value
    assert_equal 2, rules_payload.dig("classes", zephyr_id, "derived_effects", "13", "armor_multiplier")
    assert_selector "[data-character-builder-target='armorPreview']", text: "7"
    select "Starting gold instead (50 gp per level)", from: "Starting equipment"
    assert_selector "[data-character-builder-target='armorPreview']", text: "7"

    fill_in "Level", with: "12"
    assert_selector "[data-character-builder-target='armorPreview']", text: "3"
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "the Zephyr builder preview applies level-based Speed and Initiative and matches the saved sheet" do
    visit new_character_url

    fill_in "Character name", with: "Swift Zephyr Preview"
    select "Zephyr", from: "Class"
    select "Human", from: "Ancestry"
    select "Fearless", from: "Background"
    select "Standard", from: "Stat array"
    fill_in "Level", with: "2"

    assert_selector "[data-character-builder-target='speedPreview']", text: "8", exact_text: true
    assert_selector "[data-character-builder-target='initiativePreview']", text: "+6", exact_text: true

    click_on "Save draft"
    assert_text "Draft saved"

    created = Character.find_by!(name: "Swift Zephyr Preview")
    assert_equal 8, created.trait_set.speed
    assert_equal 6, created.trait_set.initiative
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "the Zephyr builder preview applies Speed and Initiative bonuses only with unarmored class gear" do
    zephyr_rules = Rules::NimbleCatalog.classes.fetch("Zephyr")
    original_gear = zephyr_rules.fetch("starting_gear")

    begin
      zephyr_rules["starting_gear"] = original_gear + [ "Rusty Mail" ]
      visit new_character_url
      select "Zephyr", from: "Class"
      select "Human", from: "Ancestry"
      select "Fearless", from: "Background"
      select "Standard", from: "Stat array"
      fill_in "Level", with: "2"

      assert_selector "[data-character-builder-target='speedPreview']", text: "6", exact_text: true
      assert_selector "[data-character-builder-target='initiativePreview']", text: "+4", exact_text: true
      assert_selector "[data-character-builder-target='derivedEffectNote']",
        text: "Level 2: not applied while wearing body armor. While unarmored, gain +2 speed and +LVL Initiative. (Heroes 2.0.1, p. 67)", exact_text: true

      select "Starting gold instead (50 gp per level)", from: "Starting equipment"
      assert_selector "[data-character-builder-target='speedPreview']", text: "8", exact_text: true
      assert_selector "[data-character-builder-target='initiativePreview']", text: "+6", exact_text: true
      assert_selector "[data-character-builder-target='derivedEffectNote']",
        text: "Level 2: applies while unarmored. While unarmored, gain +2 speed and +LVL Initiative. (Heroes 2.0.1, p. 67)", exact_text: true
    ensure
      zephyr_rules["starting_gear"] = original_gear
    end
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "editing a draft includes its currently equipped body armor in the Zephyr preview" do
    character = Character.create!(
      account: @account,
      name: "Armored Zephyr Draft",
      level: 2,
      character_class: CharacterClass.find_by!(name: "Zephyr"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "standard",
      starting_equipment_choice: "starting_gold"
    )
    character.inventory_items.create!(name: "Rusty Mail", equipped: true)

    visit edit_character_url(character)

    assert_selector "[data-character-builder-target='speedPreview']", text: "6", exact_text: true
    assert_selector "[data-character-builder-target='derivedEffectNote']",
      text: "Level 2: not applied while wearing body armor. While unarmored, gain +2 speed and +LVL Initiative. (Heroes 2.0.1, p. 67)", exact_text: true
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-07:AC-2 S-09:AC-3
  test "the Hunter builder preview cites its level-four Speed increase" do
    visit new_character_url
    select "Hunter", from: "Class"
    select "Human", from: "Ancestry"
    select "Fearless", from: "Background"
    select "Standard", from: "Stat array"
    fill_in "Level", with: "4"

    assert_selector "[data-character-builder-target='speedPreview']", text: "8", exact_text: true
    assert_selector "[data-character-builder-target='derivedEffectNote']",
      text: "Level 4: Explorer of the Wilds. +2 speed; gain a climbing speed. (Heroes 2.0.1, p. 27)", exact_text: true
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "equipping catalog armor updates Armor, slots, source details, and proficiency guidance" do
    character = Character.create!(
      account: @account,
      name: "Armored Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced",
      starting_equipment_choice: "starting_gold"
    )
    visit character_url(character)

    starting_armor = character.reload.trait_set.armor
    fill_in "Add item or stack", with: "Rusty Mail"
    click_on "Add item"
    assert_text "Rusty Mail added to inventory."
    row = find(".inventory-item-row")
    item_id = row["data-inventory-item-id"]
    assert_equal "Rusty Mail", row.find("input[name$='[name]']").value
    assert_equal "2", row.find("input[name$='[slots]']").value
    assert_includes row.text, "Cost 15 gp"
    assert_equal starting_armor, character.trait_set.armor

    row.find("input[type='checkbox']").check
    within(row) { click_on "Save item" }

    assert_text "Inventory item updated."
    row = find("[data-inventory-item-id='#{item_id}']")
    assert_includes row.text, "Equipped"
    assert_equal "1", row.find("input[name$='[slots]']").value
    assert_equal 5, character.reload.trait_set.armor
    assert_equal "Rusty Mail", row.find("input[name$='[name]']").value
    assert_includes row.text, "+6 Armor to total"
    assert_includes row.text, "Not proficient with mail armor"
    assert_includes row.text, "Defend while wearing it costs 1 additional action"
    assert_includes row.text, "Core Rules 2.0.1, p. 33"
    assert_equal true, character.character_revisions.order(:id).last.snapshot.fetch("inventory_items").find { |item| item.fetch("name") == "Rusty Mail" }.fetch("equipped")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "untrained armor Defend guidance follows its structured action surcharge" do
    character = Character.create!(
      account: @account,
      name: "Armor Rule Preview",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced",
      starting_equipment_choice: "starting_gold"
    )
    armor = character.inventory_items.create!(name: "Rusty Mail", equipped: true)
    penalty = Rules::NimbleCatalog.equipment_armor_rules.fetch("nonproficient_worn_armor")
    original_penalty = penalty.dup

    begin
      penalty["defend_action_surcharge"] = 2
      visit character_url(character)

      row = find("[data-inventory-item-id='#{armor.id}']")
      assert_includes row.text, "Defend while wearing it costs 2 additional actions"
      find("summary", text: /Slot rules/).click
      assert_text "Defending while wearing body armor without its listed proficiency costs 2 additional actions."
      assert_text "Core Rules 2.0.1, p. 32"
    ensure
      penalty.replace(original_penalty)
    end
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "the sheet explains and blocks armor with an unmet STR requirement" do
    character = Character.create!(
      account: @account,
      name: "Understrength Armor Mage",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced",
      starting_equipment_choice: "starting_gold"
    )
    visit character_url(character)
    armor_before = find(".vital-card:nth-child(2)").find("strong").text.to_i
    fill_in "Add item or stack", with: "Rusty Plate"
    click_on "Add item"

    row = find(".inventory-item-row")
    item_id = row["data-inventory-item-id"]
    assert_includes row.text, "Requires STR 2 (current STR 1)"
    assert_includes row.text, "Armor benefit is not applied until the requirement is met"
    revisions_before = character.character_revisions.count

    row.find("input[type='checkbox']").check
    within(row) { click_on "Save item" }

    assert_text "Equipped requires at least STR 2"
    row = find("[data-inventory-item-id='#{item_id}']")
    assert_not row.find("input[type='checkbox']").checked?
    assert_equal "2", row.find("input[name$='[slots]']").value
    assert_equal armor_before, find(".vital-card:nth-child(2)").find("strong").text.to_i
    assert_equal revisions_before, character.character_revisions.count
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "removing a starting shield immediately recalculates live Armor" do
    character = Character.create!(
      account: @account,
      name: "Disarmed Oathsworn",
      character_class: CharacterClass.find_by!(name: "Oathsworn"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    shield = character.starting_gear_inventory_items.find_by!(name: "Wooden Buckler")

    visit character_url(character)
    original_armor = find(".vital-card:nth-child(2)").find("strong").text.to_i
    row = find("[data-inventory-item-id='#{shield.id}']")
    accept_confirm("Remove Wooden Buckler from inventory?") do
      within(row) { click_on "Remove" }
    end

    assert_text "Wooden Buckler removed from inventory."
    assert_equal original_armor - 2, find(".vital-card:nth-child(2)").find("strong").text.to_i
    assert_no_selector "[data-inventory-item-id='#{shield.id}']"
  end

  test "choosing Academy Dropout reveals its Utility Spell picker" do
    visit new_character_url

    select "Academy Dropout", from: "Background"
    assert_selector "[data-character-builder-target='backgroundSpellChoiceField']", visible: true
    select "Wind · Wind Whisper", from: "Academy Dropout · Utility Spell"

    assert_equal "Wind Whisper", find("select[name='character[spell_choices][Academy Dropout][1][]']").value
  end

  # S-02:AC-4 S-05:AC-1 S-05:AC-3 S-09:AC-3
  test "changing away from a background clears its now-invalid spell choice" do
    visit new_character_url

    select "Academy Dropout", from: "Background"
    select "Wind · Wind Whisper", from: "Academy Dropout · Utility Spell"
    select "Fearless", from: "Background"
    assert_selector "[data-character-builder-target='backgroundSpellChoiceField']", visible: false

    select "Academy Dropout", from: "Background"
    spell_choice = find("select[name='character[spell_choices][Academy Dropout][1][]']")
    assert_equal "", spell_choice.value
  end

  # S-02:AC-1 S-02:AC-4 S-05:AC-1 S-05:AC-3 S-09:AC-3
  test "builder renders the configured number of distinct background spell picks" do
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
      visit new_character_url
      select "Mage", from: "Class"
      select "Human", from: "Ancestry"
      select background_name, from: "Background"
      select "Balanced", from: "Stat array"
      assert_selector "[data-character-builder-target='backgroundSpellChoiceField']", visible: true

      select "Wind · Wind Whisper", from: "#{background_name} · Utility Spell 1"
      select "Fire · Firebrand", from: "#{background_name} · Utility Spell 2"
      assert_selector "select[name='character[spell_choices][#{background_name}][1][]']", count: 2
      choices = all("select[name='character[spell_choices][#{background_name}][1][]']").map(&:value)
      assert_equal [ "Wind Whisper", "Firebrand" ], choices
    ensure
      catalog["background_spell_choices"] = original_choices
    end
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

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "a Spellblade records Firebrand's free Enchant Weapon cast with Initiative" do
    spellblade = Character.create!(
      account: @account,
      name: "Firebrand System Hero",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Commander"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    spellblade.update_columns(subclass_name: "Spellblade", status: "playable")
    stat_values = Character::STAT_NAMES.index_with { |stat| spellblade.stat_value(stat) }
    tracks = spellblade.derived_resource_tracks_for(stat_values:, level: 3, subclass_name: "Spellblade")
    spellblade.trait_set.update!(resource_tracks: tracks)
    actions_before = spellblade.trait_set.current_actions

    visit character_url(spellblade)

    assert_text "Cast Enchant Weapon for free when you roll Initiative"
    check "Use Firebrand to cast Enchant Weapon for free now"
    fill_in "Weapon or wielder", with: "Silver longsword"
    click_on "Record Initiative Roll · gain 1 mana"

    assert_text "Firebrand cast Enchant Weapon at Tier 2 for free on Silver longsword"
    revision = spellblade.character_revisions.find_by!(event_type: "initiative_roll")
    assert_includes revision.summary, "Heroes 2.0.1, p. 77"
    assert_equal actions_before, spellblade.reload.trait_set.current_actions
    assert_equal 1, spellblade.trait_set.resource_tracks.find { |track| track.fetch("key") == "spellblade_initiative_mana" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "a Shadowpath records its free mark and tracks Ambusher's first attack advantage" do
    hunter = Character.create!(
      account: @account,
      name: "Ambusher System Hero",
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
    actions_before = hunter.trait_set.current_actions

    visit character_url(hunter)

    assert_text "When you roll Initiative, you may use Hunter's Mark for free"
    check "Use Ambusher's free Hunter's Mark now"
    fill_in "Quarry or quarries", with: "Ashen Stag"
    click_on "Record Initiative Roll · ready Ambusher advantage"

    assert_text "Ambusher used Hunter's Mark for free on Ashen Stag"
    assert_equal 1, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadowpath_first_attack_advantage" }.fetch("current")
    assert_equal actions_before, hunter.trait_set.current_actions

    click_on "Record first attack · spend Ambusher advantage"

    assert_text "Applied Ambusher's advantage to the first attack this encounter"
    assert_equal 0, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "shadowpath_first_attack_advantage" }.fetch("current")
    assert_equal 1, hunter.character_revisions.where(event_type: "shadowpath_first_attack_advantage").count
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "a Fang and Claw Stormshifter can choose Swiftshift without Beastshift temp HP" do
    stormshifter = Character.create!(
      account: @account,
      name: "Swiftshift System Hero",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Stormshifter"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    stormshifter.update_columns(subclass_name: "Circle of Fang & Claw", status: "playable")
    stat_values = Character::STAT_NAMES.index_with { |stat| stormshifter.stat_value(stat) }
    tracks = stormshifter.derived_resource_tracks_for(stat_values:, level: 3, subclass_name: "Circle of Fang & Claw")
    stormshifter.trait_set.update!(resource_tracks: tracks)
    beastshift_before = tracks.find { |track| track.fetch("key") == "beastshift" }.fetch("current")
    temp_hp_before = stormshifter.trait_set.temp_hp

    visit character_url(stormshifter)

    assert_text "When you roll Initiative, you may Beastshift or move for free"
    check "Use Swiftshift's free choice at Initiative"
    select "Move", from: "Choose Swiftshift option"
    click_on "Record Initiative Roll · confirm optional features"

    assert_text "Swiftshift chose Move for free on Initiative"
    initiative_tracks = stormshifter.reload.character_revisions.where(event_type: "initiative_roll").sole.snapshot.dig("traits", "resource_tracks")
    assert_equal beastshift_before, initiative_tracks.find { |track| track.fetch("key") == "beastshift" }.fetch("current")
    assert_equal temp_hp_before, stormshifter.trait_set.temp_hp
    assert_no_text "Initiative recorded; no optional feature action taken"

    click_on "End Encounter · refresh uses"
    assert_text "Encounter ended. Encounter-reset counters were refreshed."
    assert_nil stormshifter.reload.encounter_started_at
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "a Wild Heart records free-movement triggers at Initiative and on a Thrill gain" do
    hunter = Character.create!(
      account: @account,
      name: "High Ground System Hero",
      level: 3,
      character_class: CharacterClass.find_by!(name: "Hunter"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    hunter.update_column(:subclass_name, "Wild Heart")
    stat_values = Character::STAT_NAMES.index_with { |stat| hunter.stat_value(stat) }
    hunter.trait_set.update!(resource_tracks: hunter.derived_resource_tracks_for(stat_values:, level: 3, subclass_name: "Wild Heart"))

    visit character_url(hunter)
    assert_text "When you roll Initiative or gain one or more Thrill of the Hunt charges, move up to half your speed for free, ignoring difficult terrain."
    assert_text "Saving an increased charge total automatically records this triggered free movement. Save separate gain events separately; resolve up to half speed ignoring difficult terrain at the table. Heroes 2.0.1, p. 29."
    click_on "Record Initiative Roll · resolve triggered movement"

    assert_text "I Have the High Ground triggered its free movement on Initiative"
    assert_includes hunter.character_revisions.where(event_type: "initiative_roll").sole.summary, "Heroes 2.0.1, p. 29"

    find("input[name='character[trait_set_attributes][resource_tracks][][current]']").fill_in with: "2"
    click_on "Save game state"
    assert_text "I Have the High Ground triggered one free movement after a gain of one or more Thrill of the Hunt charges"
    assert_text "resolve up to half speed ignoring difficult terrain at the table"
    assert_equal 2, hunter.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "thrill_of_the_hunt" }.fetch("current")
    assert_equal 1, hunter.character_revisions.where(event_type: "wild_heart_high_ground_trigger").count
    assert_not hunter.trait_set.resource_tracks.any? { |track| track.fetch("key").include?("high_ground") }, "the triggered move is recorded as an event, not banked as a resource"

    click_on "End Encounter · refresh uses"
    assert_text "Encounter ended. Encounter-reset counters were refreshed."
    ended_character = Character.find(hunter.id)
    assert_nil ended_character.encounter_started_at
    assert_equal 0, ended_character.trait_set.resource_tracks.find { |track| track.fetch("key") == "thrill_of_the_hunt" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "the sheet derives HP and Wound conditions and suggests other source-listed conditions" do
    character = Character.create!(
      account: @account,
      name: "Condition Tracker Hero",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    max_hp = character.trait_set.max_hp
    character.trait_set.update!(current_hp: max_hp / 2, current_wounds: 1)

    visit character_url(character)

    assert_selector ".derived-condition-chip", text: "Bloodied"
    assert_selector ".derived-condition-chip", text: "Wounded"
    assert_text "Death at 6 Wounds for this sheet"
    find("details.wound-death-rule-note summary").click
    assert_text "You die when you have taken 6 Wounds (unless you have an ability that changes this number)."
    assert_text "Core Rules 2.0.1, p. 9"
    assert_text "situational or unstructured maximum-Wound effects remain manual"
    assert_selector "datalist#nimble-condition-suggestions option[value='Poisoned']", visible: :all
    assert_selector "datalist#nimble-condition-suggestions option[value='Smoldering']", visible: :all
    assert_no_selector "datalist#nimble-condition-suggestions option[value='Bloodied']", visible: :all
    find("details.condition-rule-note summary").click
    assert_text "At half HP or less."
    assert_text "The tracker does not automate other condition effects or durations."

    fill_in "character_trait_set_attributes_current_hp", with: 0
    fill_in "character_trait_set_attributes_current_wounds", with: 0
    fill_in "character_conditions", with: "Poisoned, Smoldering, Inspired"
    click_on "Save game state"

    assert_text "Game state saved."
    assert_selector ".derived-condition-chip", text: "Dying"
    assert_selector ".derived-condition-chip", text: "Wounded"
    assert_text "The zero-HP rule added 1 Wound. Core Rules 2.0.1, p. 9."
    assert_equal "Poisoned, Smoldering, Inspired", character.reload.conditions
    assert_equal 2, character.trait_set.current_wounds
    assert_equal %w[Bloodied Dying Wounded], character.derived_condition_entries.map { |entry| entry.fetch("name") }
    find("details.condition-rule-note summary").click
    assert_text "While Dying, actions are limited to 1."
    assert_text "Core Rules 2.0.1, p. 9"

    fill_in "character_trait_set_attributes_current_hp", with: max_hp
    click_on "Save game state"
    assert_selector ".derived-condition-panel"
    assert_selector ".derived-condition-chip", text: "Wounded"
    assert_no_selector ".derived-condition-chip", text: "Bloodied"
    assert_no_selector ".derived-condition-chip", text: "Dying"
    assert_equal max_hp, character.reload.trait_set.current_hp
    assert_equal 2, character.trait_set.current_wounds
    assert_equal "Poisoned, Smoldering, Inspired", character.reload.conditions
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "the sheet lowers Planarbeing's death threshold with its maximum Wounds" do
    planarbeing = Character.create!(
      account: @account,
      name: "Thin Veil Sheet Hero",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Planarbeing"),
      background: @background,
      stat_array: "balanced"
    )

    visit character_url(planarbeing)

    assert_text "0 / 4"
    assert_text "Death at 4 Wounds for this sheet"
    find("details.wound-death-rule-note summary").click
    assert_text "You die when you have taken 6 Wounds (unless you have an ability that changes this number)."
    assert_text "The sheet displays the character's calculated maximum Wounds as the current death threshold."
  end

  # S-02:AC-1 S-02:AC-2 S-06:AC-3 S-07:AC-2 S-09:AC-3
  test "a level-twenty Zephyr sheet shows its permanent and Dying action limits" do
    character = Character.create!(
      account: @account,
      name: "Windborne Sheet Hero",
      level: 20,
      character_class: CharacterClass.find_by!(name: "Zephyr"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    character.trait_set.update!(current_hp: 0)

    visit character_url(character)

    assert_equal "4", find("#character_trait_set_attributes_current_actions")["max"]
    find("details.condition-rule-note summary").click
    assert_text "Permanently gain 1 action (while Dying, you have a max of 2 actions)."
    assert_text "Heroes 2.0.1, p. 69"
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-07:AC-2 S-09:AC-3
  test "a level-four Berserker sheet shows Enduring Rage's Dying action limit" do
    character = Character.create!(
      account: @account,
      name: "Enduring Rage Sheet Hero",
      level: 4,
      character_class: CharacterClass.find_by!(name: "Berserker"),
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    character.trait_set.update!(current_hp: 0)

    visit character_url(character)

    find("details.condition-rule-note summary").click
    assert_text "have a max of 2 actions instead of 1"
    assert_text "Heroes 2.0.1, p. 8"
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-07:AC-2 S-09:AC-1 S-09:AC-3
  test "the sheet explains and tracks a limited-use ancestry ability" do
    character = Character.create!(
      account: @account,
      name: "Lucky Sheet Hero",
      character_class: @character_class,
      ancestry: Ancestry.find_by!(name: "Halfling"),
      background: @background,
      stat_array: "balanced"
    )

    visit character_url(character)

    assert_text "Elusive · save success"
    assert_text "Core Rules 2.0.1, p. 23"
    find(".resource-summary-item .resource-rule-note summary").click
    assert_text "If you fail a save, you can succeed instead, 1/Safe Rest."
    find("label", text: /Elusive · save success/).find("input[type='number']").set(0)
    click_on "Save game state"

    assert_text "Game state saved"
    assert_equal 0, character.reload.trait_set.resource_tracks.find { |track| track.fetch("key") == "ancestry_halfling_elusive" }.fetch("current")
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "the sheet completes a source-backed Safe Rest" do
    character = Character.create!(
      account: @account,
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
      account: @account,
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

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "the sheet advances Oozeling Hit Dice and uses their maximum without asking for a roll" do
    character = Character.create!(
      account: @account,
      name: "Odd Constitution Sheet Hero",
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Oozeling/Construct"),
      background: @background,
      stat_array: "standard",
      stat_assignments: { strength: 0, dexterity: 2, intelligence: 2, will: -1 }
    )
    character.trait_set.update!(current_hp: 0, current_hit_dice: 1)

    visit character_url(character)

    assert_text "1D8"
    assert_text "using its maximum result"
    assert_text "Magical healing always restores the minimum amount"
    assert_text "Core Rules 2.0.1, p. 26"
    assert_no_selector "#catch_breath_die_rolls"
    click_on "Catch Breath · 10 min"

    assert_text "Catch Breath complete: recovered 8 HP."
    assert_equal 8, character.reload.trait_set.current_hp
    assert_equal 0, character.trait_set.current_hit_dice
  end

  # S-02:AC-1 S-02:AC-2 S-09:AC-1 S-09:AC-3
  test "the sheet tracks item slots, flags over-capacity loads, and lets gear be edited" do
    visit character_url(@character)

    capacity = @character.reload.inventory_slots_capacity
    fill_in "Add item or stack", with: "Oversized treasure"
    fill_in "Slots used", with: capacity + 1
    click_on "Add item"

    assert_text "Oversized treasure"
    assert_text "Over capacity by 1 slot."
    item = @character.reload.inventory_items.find_by!(name: "Oversized treasure")
    row = find("[data-inventory-item-id='#{item.id}']")
    row.find("input[name$='[slots]']").set("2")
    within(row) { click_on "Save item" }

    assert_text "Inventory item updated."
    assert_text "2 / #{capacity} slots used"
    item.reload
    row = find("[data-inventory-item-id='#{item.id}']")
    accept_confirm("Remove Oversized treasure from inventory?") do
      within(row) { click_on "Remove" }
    end

    assert_text "Oversized treasure removed from inventory."
    assert_text "0 / #{capacity} slots used"
    assert_not InventoryItem.exists?(item.id)
  end

  # S-02:AC-1 S-02:AC-2 S-03:AC-3 S-05:AC-2 S-09:AC-1 S-09:AC-3
  test "a class starting item can be removed without returning on later sheet updates" do
    character = Character.create!(
      account: @account,
      name: "Tracked Starting Gear Hero",
      character_class: @character_class,
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced"
    )
    battleaxe = character.starting_gear_inventory_items.find_by!(name: "Battleaxe")

    visit character_url(character)
    row = find("[data-inventory-item-id='#{battleaxe.id}']")
    accept_confirm("Remove Battleaxe from inventory?") do
      within(row) { click_on "Remove" }
    end

    assert_text "Battleaxe removed from inventory."
    assert_equal 2, character.reload.inventory_slots_used
    character.update!(game_notes: "The battleaxe was sold in town.")
    visit character_url(character)

    assert_no_selector "[data-inventory-item-id='#{battleaxe.id}']"
    assert_text "2 / #{character.reload.inventory_slots_capacity} slots used"
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
