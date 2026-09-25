require "test_helper"
require "stringio"

# S-01:AC-7 S-01:AC-8 S-03:AC-6 S-04:AC-1 S-10:AC-1 S-10:AC-2 S-10:AC-3 S-10:AC-4 S-10:AC-5 S-10:AC-6 S-10:AC-7 S-10:AC-8 S-10:AC-9
class CharacterImportServiceTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Berserker")
    @account = Account.create!(display_name: "Importer", email: "importer-#{SecureRandom.hex(4)}@example.com")
    @ruleset = RulesetVersion.find_by!(name: "Nimble", version: "v2.0.1")
  end

  test "a valid level-one JSON import is rule-checked and saved as an owned draft" do
    source = build_payload(create_valid_character)
    source["character"].merge!("status" => "playable", "account_id" => Account.create!(display_name: "Spoof", email: "spoof-#{SecureRandom.hex(4)}@example.com").id)

    result = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)

    assert result.success?, result.errors.to_sentence
    imported = result.character
    assert_equal @account, imported.account
    assert imported.draft?
    assert_equal source.dig("character", "name"), imported.name
    assert_equal source.fetch("stats"), imported.stat_set.attributes.slice(*Character::STAT_NAMES).transform_values(&:to_i).stringify_keys
    assert_equal "created", imported.character_revisions.order(:id).first.event_type
    assert_equal "imported", imported.character_revisions.order(:id).last.event_type
    assert_equal source.dig("traits", "max_hp"), imported.trait_set.max_hp
  end

  test "an edited draft exports its validated level-one snapshot instead of its incomplete creation event" do
    character = Character.create!(name: "Started Incomplete", level: 1)
    character.update!(
      character_class: CharacterClass.find_by!(name: "Berserker"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      ruleset_version: @ruleset,
      stat_array: "balanced"
    )
    character.skill_set.update!(might: character.skill_value(:might) + 4)
    stats = character.stat_set.attributes.slice(*Character::STAT_NAMES).transform_values(&:to_i)
    language_count = character.language_choice_count(stats)
    character.update!(language_choices: character.language_choice_options_for(stats, excluding: []).first(language_count))
    character.finalize_creation!

    exported = build_payload(character)
    original_creation = character.character_revisions.find_by!(event_type: "created").snapshot
    finalized_creation = character.character_revisions.find_by!(event_type: "finalized").snapshot

    assert_equal finalized_creation, exported.fetch("creation")
    assert_not_equal original_creation.fetch("stats"), exported.dig("creation", "stats")
    result = CharacterImportService.call(upload: upload(JSON.generate(exported)), account: @account)
    assert result.success?, result.errors.to_sentence
  end

  test "a level-one spellcaster import preserves a legal selected spell from the creation baseline" do
    spell = Spell.find_by!(school: "Fire", tier: 0)
    source = build_payload(create_valid_character("Mage", spells: [ spell ]))

    result = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)

    assert result.success?, result.errors.to_sentence
    assert_includes result.character.sheet_spells.pluck(:name), spell.name
    assert_equal [ spell.name ], result.character.import_creation_snapshot.fetch("spells")
  end

  test "a higher-level JSON import replays the full level-up history and keeps its in-game trackers" do
    original = create_level_two_character
    original.trait_set.update!(
      current_hp: original.trait_set.max_hp - 3,
      current_wounds: 1,
      current_hit_dice: original.trait_set.max_hit_dice - 1,
      current_actions: 1
    )
    original.update!(current_gold: 43)
    original.inventory_items.create!(name: "Travel journal", slots: 1)
    source = build_payload(original)

    result = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)

    assert result.success?, result.errors.to_sentence
    imported = result.character
    assert imported.draft?
    assert_equal 2, imported.level
    assert_equal original.stat_set.attributes.slice(*Character::STAT_NAMES), imported.stat_set.attributes.slice(*Character::STAT_NAMES)
    assert_equal original.skill_set.attributes.slice(*Character::SKILL_NAMES), imported.skill_set.attributes.slice(*Character::SKILL_NAMES)
    assert_equal original.trait_set.current_hp, imported.trait_set.current_hp
    assert_equal original.trait_set.current_wounds, imported.trait_set.current_wounds
    assert_equal original.trait_set.current_hit_dice, imported.trait_set.current_hit_dice
    assert_equal original.trait_set.current_actions, imported.trait_set.current_actions
    assert_equal original.trait_set.resource_tracks, imported.trait_set.resource_tracks
    assert_equal 43, imported.current_gold
    inventory_fields = %w[name slots starting_gear source_ref catalog_slots equipped]
    original_inventory = original.inventory_items.order(:name).map { |item| item.attributes.slice(*inventory_fields) }
    imported_inventory = imported.inventory_items.order(:name).map { |item| item.attributes.slice(*inventory_fields) }
    assert_equal original_inventory, imported_inventory
    assert_equal original.level_ups.first.attributes.slice(*CharacterImportService::LEVEL_UP_FIELDS), imported.level_ups.first.attributes.slice(*CharacterImportService::LEVEL_UP_FIELDS)
    assert_equal 1, imported.character_revisions.where(event_type: "level_up").count
    assert_empty imported.creation_issues
    assert_not imported.update(level: 3)
    assert_equal 2, imported.reload.level

    imported.finalize_creation!
    assert imported.reload.playable?
  end

  test "an imported draft cannot finalize if its verified progression ledger is broken" do
    imported = CharacterImportService.call(
      upload: upload(JSON.generate(build_payload(create_level_two_character))),
      account: @account
    ).character
    imported.level_ups.first.destroy!

    assert_not imported.legal_for_creation?
    assert_includes imported.creation_issues.map { |issue| issue.fetch(:message) }, "The imported level-up history does not match the character's current level."
    assert_raises(ActiveRecord::RecordInvalid) { imported.finalize_creation! }
    assert imported.reload.draft?
  end

  test "a multi-level import replays the subclass decision and every level-up input" do
    original = create_level_two_character
    level_up = original.level_ups.create!(
      from_level: 2,
      to_level: 3,
      subclass_name: original.subclass_options.first,
      skill_name: "might",
      hit_die_roll_one: 7,
      hit_die_roll_two: 3,
      feature_choices: {},
      spell_choices: {},
      language_choices: [],
      feature_language_choices: {}
    )
    LevelUpService.finalize!(level_up)
    original.reload
    source = build_payload(original)

    result = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)

    assert result.success?, result.errors.to_sentence
    assert_equal original.subclass_name, result.character.subclass_name
    assert_equal source.fetch("level_ups"), result.character.interchange_level_ups
    assert_equal source.fetch("progression"), result.character.snapshot_payload.fetch("progression")
  end

  test "the CSV interchange contract imports the same structured character data" do
    source = build_payload(create_valid_character)
    result = CharacterImportService.call(upload: upload(csv_for(source), "csv"), account: @account)

    assert result.success?, result.errors.to_sentence
    assert result.character.draft?
    assert_equal source.dig("rules", "class"), result.character.character_class.name
  end

  # S-10:AC-3 S-10:AC-4 S-10:AC-8 S-10:AC-9
  test "a higher-level CSV import replays complete level-up history and rejects omissions" do
    source = build_payload(create_level_two_character)
    result = CharacterImportService.call(upload: upload(csv_for(source), "csv"), account: @account)

    assert result.success?, result.errors.to_sentence
    assert_equal 2, result.character.level
    assert_equal source.fetch("level_ups"), result.character.interchange_level_ups
    assert_equal "draft", result.character.status

    incomplete_history = source.deep_dup
    incomplete_history["level_ups"] = []
    counts = [ Character.count, LevelUp.count, CharacterRevision.count, InventoryItem.count ]
    rejected = CharacterImportService.call(upload: upload(csv_for(incomplete_history), "csv"), account: @account)

    assert_not rejected.success?
    assert_includes rejected.errors.join(" "), "exactly 1 finalized level-up record"
    assert_equal counts, [ Character.count, LevelUp.count, CharacterRevision.count, InventoryItem.count ]

    missing_baseline = source.deep_dup
    missing_baseline.delete("creation")
    rejected_baseline = CharacterImportService.call(upload: upload(csv_for(missing_baseline), "csv"), account: @account)

    assert_not rejected_baseline.success?
    assert_includes rejected_baseline.errors.join(" "), "requires its level-1 creation snapshot and complete level-up history"
    assert_equal counts, [ Character.count, LevelUp.count, CharacterRevision.count, InventoryItem.count ]
  end

  test "a level-two import without its transition is rejected without creating rows" do
    source = build_payload(create_level_two_character)
    source["level_ups"] = []
    counts = [ Character.count, LevelUp.count, CharacterRevision.count, InventoryItem.count ]

    result = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)

    assert_not result.success?
    assert_includes result.errors.join(" "), "exactly 1 finalized level-up record"
    assert_equal counts, [ Character.count, LevelUp.count, CharacterRevision.count, InventoryItem.count ]
  end

  test "an incomplete or out-of-order transition is rejected before persistence" do
    source = build_payload(create_level_two_character)
    source["level_ups"][0].delete("hit_die_roll_two")
    incomplete = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)
    assert_not incomplete.success?
    assert_includes incomplete.errors.join(" "), "missing required fields: hit_die_roll_two"

    source = build_payload(create_level_two_character)
    source["level_ups"][0]["to_level"] = 3
    out_of_order = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)
    assert_not out_of_order.success?
    assert_includes out_of_order.errors.join(" "), "must advance from level 1 to level 2 in order"

    source = build_payload(create_level_two_character)
    source["level_ups"] << source.fetch("level_ups").first
    duplicated = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)
    assert_not duplicated.success?
    assert_includes duplicated.errors.join(" "), "exactly 1 finalized level-up record"

    source = build_payload(create_level_two_character)
    source["level_ups"][0]["hit_die_roll_one"] = 3.5
    fractional_roll = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)
    assert_not fractional_roll.success?
    assert_includes fractional_roll.errors.join(" "), "hit_die_roll_one must be an integer"
  end

  test "an illegal level-up choice rolls back the whole import and includes a rule citation" do
    source = build_payload(create_level_two_character)
    source["level_ups"][0]["skill_name"] = "not a skill"
    counts = [ Character.count, LevelUp.count, CharacterRevision.count, InventoryItem.count ]

    result = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)

    assert_not result.success?
    assert_includes result.errors.join(" "), "not a recognized skill"
    assert_includes result.errors.join(" "), "Chapter 3, Skills"
    assert_equal counts, [ Character.count, LevelUp.count, CharacterRevision.count, InventoryItem.count ]
  end

  test "a story-based subclass cannot be imported without its GM approval event" do
    commander = create_valid_character("Commander")
    source = build_payload(commander)
    source["character"]["subclass_name"] = "Spellblade"
    count = Character.count

    result = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)

    assert_not result.success?
    assert_includes result.errors.join(" "), "story-based and must go through GM approval"
    assert_equal count, Character.count
  end

  test "a supplied derived maximum that disagrees with progression is rejected instead of trusted" do
    source = build_payload(create_valid_character)
    source["traits"]["max_hp"] = -900
    count = Character.count

    result = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)

    assert_not result.success?
    assert_includes result.errors.join(" "), "traits.max_hp does not match"
    assert_equal count, Character.count
  end

  test "invalid hit-point trackers and over-capacity inventory cannot be restored" do
    source = build_payload(create_valid_character)
    source["traits"]["current_hp"] = source.dig("traits", "max_hp") + 1
    invalid_hp = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)
    assert_not invalid_hp.success?
    assert_includes invalid_hp.errors.join(" "), "traits.current_hp must be between"

    source = build_payload(create_valid_character)
    source["inventory_items"] = [ { "name" => "Oversized crate", "slots" => source.dig("traits", "inventory_slots") + 1, "equipped" => false } ]
    invalid_inventory = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)
    assert_not invalid_inventory.success?
    assert_includes invalid_inventory.errors.join(" "), "exceed the character's"

    source = build_payload(create_valid_character)
    non_armor_starting_gear = source.fetch("inventory_items").find do |item|
      item.fetch("starting_gear") && Rules::NimbleCatalog.equipment_armor_item(item.fetch("name")).blank?
    end
    non_armor_starting_gear["equipped"] = true
    invalid_equipped_item = CharacterImportService.call(upload: upload(JSON.generate(source)), account: @account)
    assert_not invalid_equipped_item.success?
    assert_includes invalid_equipped_item.errors.join(" "), "equipped is only allowed for catalog armor"
  end

  test "an import without an account remains unowned" do
    result = CharacterImportService.call(upload: upload(JSON.generate(build_payload(create_valid_character))))

    assert result.success?, result.errors.to_sentence
    assert_nil result.character.account
    assert result.character.draft?
  end

  test "unsupported extensions, versions, malformed JSON, invalid encoding, and oversized files are rejected" do
    valid = build_payload(create_valid_character)
    bad_version = valid.merge("format_version" => 2)

    assert_includes CharacterImportService.call(upload: upload("{}", "pdf"), account: @account).errors.join, ".json and .csv"
    assert_includes CharacterImportService.call(upload: upload("{", "json"), account: @account).errors.join, "malformed"
    assert_includes CharacterImportService.call(upload: upload(JSON.generate(bad_version)), account: @account).errors.join, "version"
    assert_includes CharacterImportService.call(upload: upload("\xFF".b, "json"), account: @account).errors.join, "UTF-8"
    oversized = upload("x" * (CharacterImportService::MAX_FILE_SIZE + 1), "json")
    assert_includes CharacterImportService.call(upload: oversized, account: @account).errors.join, "larger than"
  end

  test "the exported creation baseline stays at level one after level-up replay" do
    character = create_level_two_character

    payload = build_payload(character)

    assert_equal 1, payload.dig("creation", "character", "level")
    assert_equal 2, payload.dig("character", "level")
    assert_equal 1, payload.fetch("level_ups").length
    assert_equal "finalized", payload.dig("level_ups", 0, "status")
  end

  private
    def create_valid_character(class_name = "Berserker", spells: [])
      character = Character.new(
        name: "Imported #{class_name}",
        character_class: CharacterClass.find_by!(name: class_name),
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        ruleset_version: @ruleset,
        level: 1,
        stat_array: "balanced"
      )
      character.valid?
      character.skill_set.might = character.skill_set.might.to_i + 4
      stat_values = character.stat_set.attributes.slice(*Character::STAT_NAMES).transform_values(&:to_i)
      language_count = character.language_choice_count(stat_values)
      character.language_choices = character.language_choice_options_for(stat_values, excluding: []).first(language_count)
      character.spells = spells
      character.save!
      character.finalize_creation!
      character
    end

    def create_level_two_character
      character = create_valid_character
      level_up = character.level_ups.create!(
        from_level: 1,
        to_level: 2,
        skill_name: "might",
        hit_die_roll_one: 8,
        hit_die_roll_two: 4,
        feature_choices: {},
        spell_choices: {},
        language_choices: [],
        feature_language_choices: {}
      )
      LevelUpService.finalize!(level_up)
      character.reload
    end

    def build_payload(character)
      payload = character.snapshot_payload
      payload["format"] = CharacterImportService::FORMAT_NAME
      payload["format_version"] = CharacterImportService::FORMAT_VERSION
      payload["character"] = payload.fetch("character").merge("id" => character.id)
      payload["creation"] = character.import_creation_snapshot
      payload["level_ups"] = character.interchange_level_ups
      payload
    end

    def csv_for(source)
      CSV.generate do |writer|
        writer << CharacterImportService::CSV_HEADERS
        writer << CharacterImportService::CSV_HEADERS.map do |field|
          %w[format format_version].include?(field) ? source.fetch(field) : source[field].nil? ? "" : JSON.generate(source[field])
        end
      end
    end

    def upload(content, extension = "json")
      content = content.to_s
      Struct.new(:body, :original_filename) do
        def read = body
        def size = body.bytesize
      end.new(content, "character.#{extension}")
    end
end
