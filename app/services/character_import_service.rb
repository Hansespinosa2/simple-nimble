require "csv"
require "json"

class CharacterImportService
  FORMAT_NAME = "simple-nimble-character".freeze
  FORMAT_VERSION = 1
  MAX_FILE_SIZE = 1.megabyte
  CSV_HEADERS = %w[
    format format_version character rules stats skills traits spells inventory_items level_ups creation
  ].freeze
  JSON_FIELDS = %w[
    character rules stats skills traits spells inventory_items level_ups creation
  ].freeze
  LEVEL_UP_FIELDS = %w[
    from_level to_level status hit_die_roll_one hit_die_roll_two skill_name skill_from
    stat_name second_stat_name subclass_name feature_choices spell_choices language_choices
    feature_language_choices
  ].freeze
  DERIVED_TRAIT_FIELDS = %w[
    initiative speed hit_die max_hit_dice max_actions armor save_dc max_mana resource_name
    resource_formula resource_die max_resource max_hp max_wounds inventory_slots
  ].freeze
  TRACKER_FIELDS = %w[
    current_hp current_wounds current_hit_dice current_actions temp_hp current_mana current_resource
  ].freeze

  Result = Struct.new(:character, :errors, keyword_init: true) do
    def success?
      errors.empty?
    end
  end

  class Rejected < StandardError
    attr_reader :messages

    def initialize(messages)
      @messages = Array(messages)
      super(@messages.join("; "))
    end
  end

  def self.call(upload:, account: nil)
    new(upload:, account:).call
  end

  def self.template_for(kind)
    payload = {
      "format" => FORMAT_NAME,
      "format_version" => FORMAT_VERSION,
      "character" => {
        "name" => "",
        "level" => 1,
        "stat_array" => "standard",
        "stat_assignments" => {},
        "starting_equipment_choice" => "class_gear",
        "feature_choices" => {},
        "spell_choices" => {},
        "language_choices" => [],
        "feature_language_choices" => {}
      },
      "rules" => { "ruleset" => "Nimble v2.0.1", "class" => "", "ancestry" => "", "background" => "" },
      "stats" => {},
      "skills" => {},
      "traits" => {},
      "spells" => [],
      "inventory_items" => [],
      "level_ups" => []
    }

    case kind.to_s.downcase
    when "json"
      JSON.pretty_generate(payload)
    when "csv"
      CSV.generate do |csv|
        csv << CSV_HEADERS
        csv << CSV_HEADERS.map do |header|
          value = payload[header]
          %w[format format_version].include?(header) ? value : value.nil? ? "" : JSON.generate(value)
        end
      end
    else
      raise ArgumentError, "Choose the JSON or CSV template."
    end
  end

  def initialize(upload:, account: nil)
    @upload = upload
    @account = account
  end

  def call
    payload = parse_upload
    validate_format!(payload)
    imported = nil

    ActiveRecord::Base.transaction do
      imported = build_and_replay!(payload)
      imported.update!(status: "draft")
      imported.record_revision!(
        event_type: "imported",
        summary: "Imported and validated from #{upload_filename}",
        from_level: 1,
        to_level: imported.level
      )
    end

    Result.new(character: imported, errors: [])
  rescue Rejected => error
    Result.new(character: nil, errors: error.messages)
  rescue ActiveRecord::RecordInvalid => error
    Result.new(character: nil, errors: record_invalid_messages(error.record))
  end

  private
    attr_reader :upload, :account

    def parse_upload
      reject!("Choose a JSON or CSV file to import.") if upload.blank? || !upload.respond_to?(:read)
      if upload.respond_to?(:size) && upload.size.to_i > MAX_FILE_SIZE
        reject!("The import file is larger than #{MAX_FILE_SIZE / 1.megabyte} MB.")
      end

      content = upload.read.to_s
      reject!("The import file is empty.") if content.blank?
      content = content.dup.force_encoding(Encoding::UTF_8)
      reject!("The import file must use UTF-8 encoding.") unless content.valid_encoding?

      case File.extname(upload_filename).downcase
      when ".json"
        JSON.parse(content)
      when ".csv"
        parse_csv(content)
      else
        reject!("Only .json and .csv character files are supported.")
      end
    rescue JSON::ParserError => error
      reject!("The JSON file is malformed: #{error.message.lines.first.to_s.strip}")
    rescue CSV::MalformedCSVError => error
      reject!("The CSV file is malformed: #{error.message}")
    end

    def parse_csv(content)
      table = CSV.parse(content, headers: true, liberal_parsing: false)
      reject!("CSV headers must exactly match the downloadable import template.") unless table.headers == CSV_HEADERS
      reject!("CSV must contain exactly one character row.") unless table.length == 1

      row = table.first
      begin
        version = Integer(row["format_version"], 10)
      rescue ArgumentError
        reject!("CSV column `format_version` must be an integer.")
      end
      payload = { "format" => row["format"], "format_version" => version }
      JSON_FIELDS.each do |field|
        value = row[field]
        next if value.blank? && field == "creation"
        reject!("CSV column `#{field}` must contain valid JSON.") if value.blank?

        payload[field] = JSON.parse(value)
      rescue JSON::ParserError => error
        reject!("CSV column `#{field}` is invalid JSON: #{error.message.lines.first.to_s.strip}")
      end
      payload
    end

    def validate_format!(payload)
      reject!("The import document must be a JSON object.") unless payload.is_a?(Hash)
      reject!("Unsupported character format; expected `#{FORMAT_NAME}`.") unless payload["format"] == FORMAT_NAME
      reject!("Unsupported character format version; expected #{FORMAT_VERSION}.") unless payload["format_version"] == FORMAT_VERSION

      %w[character rules stats skills traits spells inventory_items level_ups].each do |field|
        reject!("Missing or invalid `#{field}` data.") unless payload.key?(field) && payload[field].is_a?(field.end_with?("items", "ups", "spells") ? Array : Hash)
      end
      reject!("`creation` must be an object when provided.") if payload.key?("creation") && payload["creation"].present? && !payload["creation"].is_a?(Hash)
    end

    def build_and_replay!(payload)
      current = payload.fetch("character")
      rules = payload.fetch("rules")
      target_level = positive_integer!(current["level"], "character.level")
      reject!("character.level must not exceed #{Character::MAX_LEVEL}.") if target_level > Character::MAX_LEVEL

      creation = payload["creation"].presence
      if creation.blank?
        reject!("A level #{target_level} import requires its level-1 creation snapshot and complete level-up history.") if target_level > 1
        creation = payload
      end
      validate_creation_snapshot!(creation, rules)
      validate_level_up_history!(payload.fetch("level_ups"), target_level)

      character = create_level_one_character!(payload, creation, current, rules)
      replay_level_ups!(character, payload.fetch("level_ups"))
      verify_replayed_state!(character, payload, creation, rules)
      restore_current_state!(character, payload)
      character
    end

    def validate_creation_snapshot!(creation, current_rules)
      valid_shape = creation["character"].is_a?(Hash) && creation["rules"].is_a?(Hash) &&
        creation["stats"].is_a?(Hash) && creation["skills"].is_a?(Hash) && creation["spells"].is_a?(Array)
      reject!("The creation snapshot must contain character, rules, stats, skills, and spells.") unless valid_shape
      reject!("The creation snapshot must start at level 1.") unless creation.dig("character", "level").to_i == 1

      %w[class ancestry background ruleset].each do |key|
        reject!("creation.rules.#{key} does not match the current character rules.") unless creation.dig("rules", key) == current_rules[key]
      end
    end

    def validate_level_up_history!(entries, target_level)
      expected_levels = (2..target_level).to_a
      reject!("Provide exactly #{expected_levels.length} finalized level-up record#{'s' unless expected_levels.length == 1} for levels #{expected_levels.join(', ')}.") unless entries.length == expected_levels.length

      entries.each_with_index do |entry, index|
        expected_level = expected_levels[index]
        reject!("level_ups[#{index}] must be an object.") unless entry.is_a?(Hash)
        missing = LEVEL_UP_FIELDS.reject { |field| entry.key?(field) }
        reject!("level_ups[#{index}] is missing required fields: #{missing.join(', ')}.") if missing.any?
        reject!("level_ups[#{index}] must be finalized.") unless entry["status"] == "finalized"
        integer!(entry["from_level"], "level_ups[#{index}].from_level")
        integer!(entry["to_level"], "level_ups[#{index}].to_level")
        unless entry["from_level"] == expected_level - 1 && entry["to_level"] == expected_level
          reject!("level_ups[#{index}] must advance from level #{expected_level - 1} to level #{expected_level} in order.")
        end
        positive_integer!(entry["hit_die_roll_one"], "level_ups[#{index}].hit_die_roll_one")
        positive_integer!(entry["hit_die_roll_two"], "level_ups[#{index}].hit_die_roll_two")
        reject!("level_ups[#{index}].feature_choices must be an object.") unless entry["feature_choices"].is_a?(Hash)
        reject!("level_ups[#{index}].spell_choices must be an object.") unless entry["spell_choices"].is_a?(Hash)
        reject!("level_ups[#{index}].language_choices must be an array.") unless entry["language_choices"].is_a?(Array)
        reject!("level_ups[#{index}].feature_language_choices must be an object.") unless entry["feature_language_choices"].is_a?(Hash)
      end
    end

    def create_level_one_character!(payload, creation, current, rules)
      klass = CharacterClass.find_by(name: rules["class"])
      ancestry = Ancestry.find_by(name: rules["ancestry"])
      background = Background.find_by(name: rules["background"])
      reject!("rules.class must exactly match a class in the Nimble catalog.") unless klass
      reject!("rules.ancestry must exactly match an ancestry in the Nimble catalog.") unless ancestry
      reject!("rules.background must exactly match a background in the Nimble catalog.") unless background

      ruleset = RulesetVersion.find_by(name: "Nimble", version: "v2.0.1")
      reject!("This app does not have the Nimble v2.0.1 ruleset available.") unless ruleset
      reject!("Only characters using #{ruleset.label} can be imported.") unless rules["ruleset"] == ruleset.label

      base_character = creation.fetch("character")
      current_character = payload.fetch("character")
      reject!("character.subclass_name is story-based and must go through GM approval before import.") if klass.story_based_subclass_rule(current_character["subclass_name"]).present?
      reject!("creation.character.subclass_name must be blank; choose the standard subclass in its recorded level-up.") if base_character["subclass_name"].present?
      reject!("Subclass-choice audit data cannot be imported; re-approve it through the GM story-change flow.") if current_character["subclass_choices"].present? && current_character["subclass_choices"] != {}

      starting_equipment_choice = base_character["starting_equipment_choice"].presence || "class_gear"
      reject!("creation.character.starting_equipment_choice is not supported.") unless Character::STARTING_EQUIPMENT_CHOICES.include?(starting_equipment_choice)

      initial_stats = canonical_values!(creation.fetch("stats"), Character::STAT_NAMES, "creation.stats")
      initial_skills = canonical_values!(creation.fetch("skills"), Character::SKILL_NAMES, "creation.skills")
      assignments = creation.dig("character", "stat_assignments")
      reject!("creation.character.stat_assignments must contain all four assigned stats.") unless assignments.is_a?(Hash)
      assignments = canonical_values!(assignments, Character::STAT_NAMES, "creation.character.stat_assignments")
      initial_spells = spell_records!(creation.fetch("spells"), "creation.spells")
      initial_feature_choices = normalize_choice_ledger(base_character["feature_choices"] || {})
      initial_spell_choices = normalize_choice_ledger(base_character["spell_choices"] || {})
      initial_language_choices = string_array!(base_character["language_choices"] || [], "creation.character.language_choices")
      initial_feature_language_choices = normalize_nested_string_values(base_character["feature_language_choices"] || {}, "creation.character.feature_language_choices")

      character = Character.new(
        account:,
        ruleset_version: ruleset,
        character_class: klass,
        ancestry:,
        background:,
        name: current_character["name"],
        race: ancestry.name,
        nimble_class: klass.name,
        level: 1,
        status: "draft",
        legacy_background_text: base_character["legacy_background_text"],
        description: current_character["description"],
        stat_array: base_character["stat_array"],
        stat_assignments: assignments,
        starting_equipment_choice:,
        spell_school_choice: base_character["spell_school_choice"],
        feature_choices: initial_feature_choices,
        spell_choices: initial_spell_choices,
        language_choices: initial_language_choices,
        feature_language_choices: initial_feature_language_choices,
        languages: base_character["languages"],
        inventory: current_character["inventory"]
      )
      character.build_stat_set
      character.stat_set.assign_attributes(initial_stats)
      character.build_skill_set
      character.skill_set.assign_attributes(initial_skills)
      character.spells = initial_spells
      character.save!

      baseline_stats = normalized_values(character.stat_set, Character::STAT_NAMES)
      reject!("creation.stats do not match the assigned level-1 stat array.") unless baseline_stats == initial_stats
      baseline_skills = normalized_values(character.skill_set, Character::SKILL_NAMES)
      reject!("creation.skills do not match the level-1 skill choices and origin bonuses.") unless baseline_skills == initial_skills

      creation_issues = character.creation_explanations
      reject!(format_rule_issues(creation_issues)) if creation_issues.any?
      character.finalize_creation!
      character
    end

    def replay_level_ups!(character, entries)
      entries.each_with_index do |entry, index|
        permitted = entry.slice(*LEVEL_UP_FIELDS, "notes")
        permitted["feature_choices"] = normalize_flat_choices(permitted["feature_choices"], "level_ups[#{index}].feature_choices")
        permitted["spell_choices"] = normalize_flat_choices(permitted["spell_choices"], "level_ups[#{index}].spell_choices")
        permitted["language_choices"] = string_array!(permitted["language_choices"], "level_ups[#{index}].language_choices")
        permitted["feature_language_choices"] = normalize_nested_string_values(permitted["feature_language_choices"], "level_ups[#{index}].feature_language_choices")
        level_up = character.level_ups.build(permitted.except("status"))
        level_up.save!
        LevelUpService.finalize!(level_up)
      rescue Rejected
        raise
      rescue ActiveRecord::RecordInvalid => error
        raise Rejected, format_level_up_errors(level_up, error)
      end
    end

    def verify_replayed_state!(character, payload, creation, rules)
      source_character = payload.fetch("character")
      source_rules = payload.fetch("rules")
      current_level = positive_integer!(source_character["level"], "character.level")
      reject!("The level-up history does not reach character.level #{current_level}.") unless character.level == current_level
      reject!("The rules class differs from the replayed character.") unless character.character_class.name == source_rules["class"]
      reject!("The rules ancestry differs from the replayed character.") unless character.ancestry.name == source_rules["ancestry"]
      reject!("The rules background differs from the replayed character.") unless character.background.name == source_rules["background"]
      reject!("character.subclass_name does not match the replayed level-up history.") unless character.subclass_name.to_s == source_character["subclass_name"].to_s

      verify_value_map!(payload.fetch("stats"), character.stat_set, Character::STAT_NAMES, "stats")
      verify_value_map!(payload.fetch("skills"), character.skill_set, Character::SKILL_NAMES, "skills")
      verify_choice_ledger!(source_character["feature_choices"], character.feature_choices, "character.feature_choices")
      verify_choice_ledger!(source_character["spell_choices"], character.spell_choices, "character.spell_choices")
      verify_string_array!(source_character["language_choices"], character.language_choices, "character.language_choices")
      verify_nested_string_values!(source_character["feature_language_choices"], character.feature_language_choices, "character.feature_language_choices")
      verify_string_array!(payload.fetch("spells"), character.sheet_spells.order(:name).pluck(:name), "spells")
      verify_string_array!(source_character["languages"].to_s.split(/,\s*/), character.languages.to_s.split(/,\s*/), "character.languages")

      base_stats = canonical_values!(creation.fetch("stats"), Character::STAT_NAMES, "creation.stats")
      reject!("The level-1 stat baseline changed during replay.") unless base_stats == normalized_values(character.stat_set, Character::STAT_NAMES) if current_level == 1
      verify_derived_traits!(payload.fetch("traits"), character)
    end

    def restore_current_state!(character, payload)
      source_character = payload.fetch("character")
      traits = payload.fetch("traits")
      character.update!(current_gold: nonnegative_integer!(source_character["current_gold"] || 0, "character.current_gold"))

      updates = {}
      TRACKER_FIELDS.each do |field|
        next unless traits.key?(field) && traits[field].present?
        updates[field.to_sym] = nonnegative_integer!(traits[field], "traits.#{field}")
      end
      validate_tracker_ranges!(character, updates)

      source_tracks = traits["resource_tracks"]
      unless source_tracks.nil?
        reject!("traits.resource_tracks must be an array.") unless source_tracks.is_a?(Array)
        tracks = Array(character.trait_set.resource_tracks).map(&:to_h).map(&:stringify_keys)
        supplied = source_tracks.each_with_object({}) do |track, result|
          reject!("Each traits.resource_tracks entry must be an object.") unless track.is_a?(Hash)
          key = track["key"].to_s
          reject!("traits.resource_tracks contains a duplicate or blank key.") if key.blank? || result.key?(key)
          result[key] = nonnegative_integer!(track["current"], "traits.resource_tracks.#{key}.current")
        end
        expected_keys = tracks.map { |track| track.fetch("key") }.sort
        reject!("traits.resource_tracks keys do not match the character's rules resources.") unless supplied.keys.sort == expected_keys
        tracks.each do |track|
          current = supplied.fetch(track.fetch("key"))
          if track["max"].present? && current > track.fetch("max").to_i
            reject!("traits.resource_tracks.#{track.fetch('key')}.current must be between 0 and #{track.fetch('max')}.")
          end
          track["current"] = current
        end
        updates[:resource_tracks] = tracks
        resource_values = character.resource_tracker_values_for(tracks)
        updates[:current_mana] = resource_values.fetch(:current_mana)
        updates[:current_resource] = resource_values.fetch(:current_resource)
        %w[current_mana current_resource].each do |field|
          next unless traits.key?(field) && traits[field].present?
          reject!("traits.#{field} conflicts with traits.resource_tracks.") unless traits[field].to_i == updates[field.to_sym].to_i
        end
      end

      character.trait_set.update!(updates) if updates.any?
      restore_inventory!(character, payload.fetch("inventory_items"))
      reject!("inventory_items exceed the character's #{character.inventory_slots_capacity} inventory slots.") if character.inventory_slots_used > character.inventory_slots_capacity
    end

    def restore_inventory!(character, rows)
      reject!("inventory_items must be an array.") unless rows.is_a?(Array)
      equipped_kinds = rows.filter_map do |row|
        next unless row.is_a?(Hash) && row["equipped"] == true

        profile = Rules::NimbleCatalog.equipment_armor_item(row["name"].to_s)
        profile.fetch("kind") if profile.present?
      end
      duplicate_kinds = equipped_kinds.tally.filter_map { |kind, count| kind if count > 1 }
      reject!("Only one item of each armor kind can be equipped at a time (#{duplicate_kinds.join(', ')}).") if duplicate_kinds.any?

      character.inventory_items.destroy_all
      starting_gear = Rules::NimbleCatalog.starting_gear_inventory_items(character.character_class.name).index_by { |item| item.fetch("name") }
      rows.each_with_index do |row, index|
        reject!("inventory_items[#{index}] must be an object.") unless row.is_a?(Hash)
        name = row["name"].to_s.strip
        reject!("inventory_items[#{index}].name is required.") if name.blank?
        %w[equipped starting_gear].each do |field|
          reject!("inventory_items[#{index}].#{field} must be true or false.") if row.key?(field) && ![ true, false ].include?(row[field])
        end
        equipped = row["equipped"] == true
        starting = row["starting_gear"] == true
        profile = Rules::NimbleCatalog.equipment_armor_item(name)
        reject!("inventory_items[#{index}].equipped is only allowed for catalog armor.") if equipped && profile.blank?
        item = starting_gear[name] if starting
        reject!("inventory_items[#{index}] claims non-canonical starting gear.") if starting && item.blank?
        if item
          expected_slots = item.fetch("slots").to_i
          expected_slots = profile.fetch("slots_worn").to_i if equipped
          if row.key?("slots")
            supplied_slots = positive_integer!(row["slots"], "inventory_items[#{index}].slots")
            reject!("inventory_items[#{index}].slots must be #{expected_slots} for this starting-gear item.") unless supplied_slots == expected_slots
          end
          character.inventory_items.create!(
            name:,
            slots: expected_slots,
            starting_gear: true,
            source_ref: item.fetch("source_ref"),
            catalog_slots: expected_slots,
            equipped:
          )
          next
        end

        slots = positive_integer!(row["slots"], "inventory_items[#{index}].slots")
        if profile.present?
          expected_slots = equipped ? profile.fetch("slots_worn").to_i : profile.fetch("slots_unworn").to_i
          reject!("inventory_items[#{index}].slots must be #{expected_slots} for this armor state.") unless slots == expected_slots
        end
        character.inventory_items.create!(name:, slots:, equipped:)
      rescue ActiveRecord::RecordInvalid => error
        raise Rejected, [ "inventory_items[#{index}]: #{error.record.errors.full_messages.to_sentence}" ]
      end
    end

    def verify_derived_traits!(source_traits, character)
      DERIVED_TRAIT_FIELDS.each do |field|
        next unless source_traits.key?(field)
        expected = character.trait_set.public_send(field)
        actual = source_traits[field]
        reject!("traits.#{field} does not match the value calculated by the level-up history (expected #{expected.inspect}).") unless actual == expected
      end
      expected_tracks = Array(character.trait_set.resource_tracks).map(&:to_h).map(&:stringify_keys)
      supplied_tracks = Array(source_traits["resource_tracks"]).map do |track|
        track.to_h.stringify_keys.except("current")
      end
      reject!("traits.resource_tracks metadata does not match the rules-derived resources.") unless supplied_tracks == expected_tracks.map { |track| track.except("current") } if source_traits.key?("resource_tracks")
    end

    def validate_tracker_ranges!(character, updates)
      maxima = {
        "current_hp" => character.trait_set.max_hp,
        "current_wounds" => character.trait_set.max_wounds,
        "current_hit_dice" => character.trait_set.max_hit_dice,
        "current_actions" => character.trait_set.max_actions,
        "current_mana" => character.trait_set.max_mana,
        "current_resource" => character.trait_set.max_resource
      }
      maxima.each do |field, maximum|
        next unless updates.key?(field.to_sym) && maximum.present?
        reject!("traits.#{field} must be between 0 and #{maximum}.") if updates[field.to_sym] > maximum.to_i
      end
    end

    def verify_value_map!(source, record, fields, path)
      values = canonical_values!(source, fields, path)
      expected = normalized_values(record, fields)
      reject!("#{path} does not match the values reconstructed from the level-up history.") unless values == expected
    end

    def canonical_values!(source, fields, path)
      reject!("#{path} must be an object.") unless source.is_a?(Hash)
      missing = fields - source.keys
      reject!("#{path} is missing #{missing.join(', ')}.") if missing.any?
      fields.index_with { |key| integer!(source[key], "#{path}.#{key}") }
    end

    def normalized_values(record, fields)
      fields.index_with { |key| record.public_send(key).to_i }
    end

    def spell_records!(names, path)
      values = string_array!(names, path)
      reject!("#{path} contains duplicate spell names.") unless values.uniq == values
      spells = values.map do |name|
        Spell.find_by(name:) || reject!("#{path} contains unknown spell `#{name}`.")
      end
      spells
    end

    def normalize_flat_choices(value, path)
      reject!("#{path} must be an object.") unless value.is_a?(Hash)
      value.each_with_object({}) do |(pool, selections), result|
        result[pool.to_s] = string_array!(selections, "#{path}.#{pool}")
      end
    end

    def normalize_choice_ledger(value)
      reject!("Choice history must be an object.") unless value.is_a?(Hash)
      value.each_with_object({}) do |(pool, selections), result|
        result[pool.to_s] = if selections.is_a?(Hash)
          selections.each_with_object({}) do |(level, selected), by_level|
            by_level[level.to_s] = string_array!(selected, "choices.#{pool}.#{level}")
          end
        else
          { "legacy" => string_array!(selections, "choices.#{pool}") }
        end
      end
    end

    def normalize_nested_string_values(value, path)
      reject!("#{path} must be an object.") unless value.is_a?(Hash)
      value.each_with_object({}) do |(key, selections), result|
        result[key.to_s] = string_array!(selections, "#{path}.#{key}")
      end
    end

    def string_array!(value, path)
      reject!("#{path} must be an array of strings.") unless value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
      value.map(&:strip).reject(&:blank?)
    end

    def verify_choice_ledger!(source, actual, path)
      expected = normalize_choice_ledger(actual || {})
      supplied = normalize_choice_ledger(source || {})
      reject!("#{path} does not match the replayed choices.") unless supplied == expected
    end

    def verify_nested_string_values!(source, actual, path)
      expected = normalize_nested_string_values(actual || {}, path)
      supplied = normalize_nested_string_values(source || {}, path)
      reject!("#{path} does not match the replayed choices.") unless supplied == expected
    end

    def verify_string_array!(source, actual, path)
      provided = string_array!(source, path)
      expected = string_array!(actual, "replayed #{path}")
      reject!("#{path} does not match the replayed character.") unless provided.sort == expected.sort
    end

    def integer!(value, path)
      reject!("#{path} must be an integer.") unless value.is_a?(Integer)
      value
    end

    def positive_integer!(value, path)
      result = integer!(value, path)
      reject!("#{path} must be greater than zero.") unless result.positive?
      result
    end

    def nonnegative_integer!(value, path)
      result = integer!(value, path)
      reject!("#{path} cannot be negative.") if result.negative?
      result
    end

    def format_rule_issues(issues)
      issues.map { |issue| "#{issue.fetch(:message)} (#{issue.fetch(:source_ref)})" }
    end

    def format_level_up_errors(level_up, error)
      explanations = LevelUpPlanner.new(level_up.character, level_up).explanations
      return explanations.map { |issue| "level_ups[#{level_up.to_level.to_i - 2}]: #{issue.fetch(:message)} (#{issue.fetch(:source_ref)})" } if explanations.any?

      [ "level_ups[#{level_up.to_level.to_i - 2}]: #{error.record.errors.full_messages.to_sentence}" ]
    end

    def record_invalid_messages(record)
      if record.is_a?(LevelUp) && record.persisted?
        return format_level_up_errors(record, ActiveRecord::RecordInvalid.new(record))
      end

      record.errors.full_messages.presence || [ "The imported character could not be saved." ]
    end

    def upload_filename
      upload.respond_to?(:original_filename) ? upload.original_filename.to_s : "character.json"
    end

    def reject!(message)
      raise Rejected, message
    end
end
