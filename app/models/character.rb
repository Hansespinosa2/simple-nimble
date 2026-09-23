class Character < ApplicationRecord
  serialize :stat_assignments, coder: JSON
  serialize :feature_choices, coder: JSON
  serialize :spell_choices, coder: JSON

  BASE_SPEED = 6
  DEFAULT_MAX_WOUNDS = 6
  BASE_INVENTORY_SLOTS = 10

  # Nimble creation-time stat arrays (02-rules-canon.md S-1 #1). The builder
  # recommends placing the highest values in Key Stats, but the rules allow
  # the player to place each array value freely.
  STAT_ARRAYS = {
    "standard" => [ 2, 2, 0, -1 ],
    "balanced" => [ 2, 1, 1, 0 ],
    "min_max"  => [ 3, 1, -1, -1 ]
  }.freeze

  STAT_NAMES = %w[strength dexterity intelligence will].freeze
  SKILL_TO_STAT = {
    "arcana" => "intelligence",
    "examination" => "intelligence",
    "finesse" => "dexterity",
    "influence" => "will",
    "insight" => "will",
    "lore" => "intelligence",
    "might" => "strength",
    "naturecraft" => "will",
    "perception" => "will",
    "stealth" => "dexterity"
  }.freeze
  SKILL_NAMES = SKILL_TO_STAT.keys.freeze

  STAT_INCREASE_LEVELS = {
    "key" => [ 4, 8, 12, 16 ],
    "secondary" => [ 5, 9, 13, 17 ],
    "any_two" => [ 20 ]
  }.freeze

  STATUS_LABELS = {
    "draft" => "Draft",
    "playable" => "Playable",
    "level_up" => "Level-up in progress"
  }.freeze

  has_one :stat_set, dependent: :destroy
  has_one :skill_set, dependent: :destroy
  has_one :trait_set, dependent: :destroy

  accepts_nested_attributes_for :stat_set
  accepts_nested_attributes_for :skill_set
  accepts_nested_attributes_for :trait_set

  has_many :character_spells, dependent: :destroy
  has_many :spells, through: :character_spells
  has_many :character_revisions, dependent: :destroy
  has_many :level_ups, dependent: :destroy
  has_many :character_shares, dependent: :destroy
  has_many :campaigns, through: :character_shares

  # Rules-canon references (spec 02/05). Optional at the model level because
  # 3 pre-existing characters predate this slice of canon and were never
  # backfilled with a guess; the creation flow is what actually requires
  # them (see #legal_for_creation? and CharactersController).
  belongs_to :character_class, optional: true
  belongs_to :ancestry, optional: true
  belongs_to :background, optional: true
  belongs_to :ruleset_version, optional: true
  belongs_to :account, optional: true

  validates :stat_array, inclusion: { in: STAT_ARRAYS.keys }, allow_blank: true
  validates :status, inclusion: { in: STATUS_LABELS.keys }
  validates :level, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 20 }, allow_nil: true
  validate :stat_assignments_match_array
  validate :playable_state_is_legal, if: :playable?

  before_create :ensure_defaults
  before_validation :assign_default_ruleset
  before_validation :sync_derived_values, if: :should_sync_derived_values?
  after_commit :record_initial_revision, on: :create

  scope :drafts, -> { where(status: "draft") }
  scope :playable, -> { where(status: "playable") }
  scope :in_level_up, -> { where(status: "level_up") }

  def draft?
    status == "draft"
  end

  def playable?
    status == "playable"
  end

  def level_up_in_progress?
    status == "level_up"
  end

  def status_label
    STATUS_LABELS.fetch(status, status.to_s.humanize)
  end

  def rules_context_label
    ruleset_version&.label || "Nimble v2.0.1 · legacy context"
  end

  def rules_source_reference
    ruleset_version&.source_reference || "Nimble v2.0.1 · Core Rules, Character Creation"
  end

  def legal_for_creation?
    creation_issues.empty?
  end

  def known_spell_schools
    schools = character_class&.spell_schools || []
    schools = schools.reject { |school| school == "choice" }
    schools << spell_school_choice if character_class&.spell_schools&.include?("choice") && spell_school_choice.present?
    schools.uniq
  end

  def subclass_options
    character_class&.subclass_options || []
  end

  def available_spells
    spells = Spell.order(:tier, :name)
    return Spell.none if character_class.blank?

    spells.select { |spell| spell.available_to?(self) }
  end

  def starting_equipment_summary
    character_class&.starting_gear&.join(", ")
  end

  def progression_features_through(level = self.level)
    return [] if character_class.blank?

    level = level.presence || 1

    1.upto([ level.to_i, 20 ].min).flat_map do |feature_level|
      character_class.features_for(feature_level).map do |name|
        { level: feature_level, name: name }
      end
    end
  end

  def subclass_progression_features_through(level = self.level)
    return [] if character_class.blank? || subclass_name.blank?

    level = level.presence || 1

    1.upto([ level.to_i, 20 ].min).flat_map do |feature_level|
      character_class.subclass_features_for(subclass_name, feature_level).map do |name|
        { level: feature_level, name: name }
      end
    end
  end

  def recorded_feature_choices
    feature_choice_ledger.transform_values do |selections_by_level|
      selections_by_level.values.flatten.compact_blank.map(&:to_s)
    end
  end

  def feature_choice_ledger
    feature_choices.to_h.stringify_keys.transform_values do |selections|
      if selections.respond_to?(:to_h) && !selections.is_a?(Array)
        selections.to_h.stringify_keys.transform_values { |level_selections| Array(level_selections).compact_blank.map(&:to_s) }
      else
        { "legacy" => Array(selections).compact_blank.map(&:to_s) }
      end
    end
  end

  def feature_choice_pools_through(level = self.level)
    return [] if character_class.blank?

    level = level.presence || 1
    ledger = feature_choice_ledger

    1.upto([ level.to_i, 20 ].min).flat_map do |feature_level|
      character_class.feature_choice_pools_for(feature_level).map do |pool|
        pool.merge(
          "level" => feature_level,
          "selected" => feature_choice_selections_for(pool.fetch("name"), feature_level, ledger)
        )
      end
    end
  end

  def feature_choice_entries_through(level = self.level)
    feature_choice_pools_through(level).filter_map do |pool|
      next if pool.fetch("selected").empty?

      {
        level: pool.fetch("level"),
        name: pool.fetch("name"),
        selected: pool.fetch("selected"),
        source_ref: pool.fetch("source_ref")
      }
    end
  end

  def feature_choice_selections_for(pool_name, level, ledger = feature_choice_ledger)
    selections_by_level = ledger.fetch(pool_name.to_s, {})
    return selections_by_level.fetch(level.to_i.to_s, []) if selections_by_level.key?(level.to_i.to_s)
    return [] unless selections_by_level.key?("legacy")

    first_level = 1.upto([ level.to_i, 20 ].min).find do |candidate_level|
      character_class.feature_choice_pools_for(candidate_level).any? { |pool| pool.fetch("name") == pool_name.to_s }
    end
    level.to_i == first_level ? selections_by_level.fetch("legacy") : []
  end

  def spell_choice_ledger
    spell_choices.to_h.stringify_keys.transform_values do |selections|
      if selections.respond_to?(:to_h) && !selections.is_a?(Array)
        selections.to_h.stringify_keys.transform_values { |level_selections| Array(level_selections).compact_blank.map(&:to_s) }
      else
        { "legacy" => Array(selections).compact_blank.map(&:to_s) }
      end
    end
  end

  def recorded_spell_choices
    spell_choice_ledger.transform_values do |selections_by_level|
      selections_by_level.values.flatten.compact_blank.map(&:to_s)
    end
  end

  def spell_choice_pools_for(level)
    pools = character_class&.spell_choice_pools_for(level).to_a
    background_pool = starting_background_spell_choice_pool
    if level.to_i == 1 && background_pool.present?
      pools << background_pool
    end

    pools.flat_map do |pool|
      case pool.fetch("kind")
      when "utility_school"
        [ pool.merge("options" => Array(pool.fetch("allowed_schools", []))) ]
      when "utility_spell"
        [ pool.merge("options" => utility_spell_options(pool.fetch("allowed_schools", []))) ]
      when "utility_spell_any"
        [ pool ]
      when "utility_spell_each_known_school"
        known_spell_schools.map do |school|
          pool.merge(
            "name" => "#{pool.fetch('name')} (#{school})",
            "base_name" => pool.fetch("name"),
            "school" => school,
            "options" => utility_spell_options([ school ])
          )
        end
      else
        []
      end
    end
  end

  def spell_choice_pools_through(level = self.level, ledger: spell_choice_ledger)
    level = level.presence || 1

    1.upto([ level.to_i, 20 ].min).flat_map do |choice_level|
      spell_choice_pools_for(choice_level).map do |pool|
        pool.merge(
          "level" => choice_level,
          "selected" => spell_choice_selections_for(pool.fetch("name"), choice_level, ledger)
        )
      end
    end
  end

  def spell_choice_entries_through(level = self.level)
    spell_choice_pools_through(level).filter_map do |pool|
      next if pool.fetch("selected").empty?

      {
        level: pool.fetch("level"),
        name: pool.fetch("name"),
        selected: pool.fetch("selected"),
        source_ref: pool.fetch("source_ref")
      }
    end
  end

  def spell_choice_selections_for(pool_name, level, ledger = spell_choice_ledger)
    selections_by_level = ledger.fetch(pool_name.to_s, {})
    return selections_by_level.fetch(level.to_i.to_s, []) if selections_by_level.key?(level.to_i.to_s)
    return [] unless selections_by_level.key?("legacy")

    first_level = 1.upto([ level.to_i, 20 ].min).find do |candidate_level|
      spell_choice_pools_for(candidate_level).any? { |pool| pool.fetch("name") == pool_name.to_s }
    end
    level.to_i == first_level ? selections_by_level.fetch("legacy") : []
  end

  def utility_spell_names(level: self.level, ledger: spell_choice_ledger)
    utility_schools = Spell.where(tier: -1).distinct.pluck(:school)
    selections = spell_choice_pools_through(level, ledger: ledger).flat_map do |pool|
      pool.fetch("selected") & Array(pool.fetch("options"))
    end
    auto_grants = character_class&.spell_auto_grants_for(level.to_i.positive? ? level : 1) || []
    auto_schools = auto_grants.include?("known") ? known_spell_schools : auto_grants
    schools = (selections & utility_schools) + auto_schools
    direct_names = selections - utility_schools

    Spell.where(tier: -1, school: schools).pluck(:name) + direct_names
  end

  def granted_utility_spells(level: self.level, ledger: spell_choice_ledger)
    Spell.where(name: utility_spell_names(level:, ledger:))
  end

  def sync_granted_utility_spells!(level: self.level, ledger: spell_choice_ledger)
    self.spells = (spells.to_a + granted_utility_spells(level:, ledger:).to_a).uniq
  end

  def take_safe_rest!
    transaction do
      tracks = resource_tracks_after_safe_rest
      resource_values = resource_tracker_values_for(tracks)
      trait_set.update!(
        current_hp: trait_set.max_hp,
        current_hit_dice: trait_set.max_hit_dice,
        current_wounds: [ trait_set.current_wounds.to_i - 1, 0 ].max,
        temp_hp: 0,
        current_mana: resource_values.fetch(:current_mana) || trait_set.max_mana,
        current_resource: resource_values.fetch(:current_resource) || trait_set.max_resource,
        resource_tracks: tracks
      )
      record_revision!(event_type: "safe_rest", summary: "Safe Rest completed", from_level: level, to_level: level)
    end
  end

  def derived_feature_effects(level: self.level, subclass_name: self.subclass_name)
    return {} if character_class.blank?

    Rules::NimbleCatalog.derived_effects_for(character_class.name, subclass_name, level.to_i.positive? ? level : 1)
  end

  def hit_die_for(level: self.level, subclass_name: self.subclass_name)
    derived_feature_effects(level:, subclass_name:).fetch("hit_die", character_class&.hit_die || "1d6")
  end

  def initiative_for(stat_values = nil, level: self.level, subclass_name: self.subclass_name)
    values = stat_values || current_stat_values
    level_value = level.to_i.positive? ? level.to_i : 1
    level_bonus = derived_feature_effects(level:, subclass_name:)["initiative_level_bonus"] ? level_value : 0
    value_for_stat(values, "dexterity") + derived_modifier_for(:initiative_modifier, level:, subclass_name:) + level_bonus
  end

  def speed_for(level: self.level, subclass_name: self.subclass_name)
    BASE_SPEED + derived_modifier_for(:speed_modifier, level:, subclass_name:)
  end

  def save_dc_for(stat_values = nil)
    return nil if character_class.blank?

    values = stat_values || current_stat_values
    10 + character_class.key_stats.map { |stat| value_for_stat(values, stat) }.max.to_i
  end

  def armor_for(stat_values = nil, level: self.level, subclass_name: self.subclass_name)
    return nil if character_class.blank?

    values = stat_values || current_stat_values
    rules = character_class.armor_rules
    dexterity = value_for_stat(values, "dexterity")
    base = rules.fetch("base", 0).to_i

    armor = case rules.fetch("formula", "dexterity")
    when "dexterity_plus_strength"
      base + dexterity + value_for_stat(values, "strength")
    else
      cap = rules["dexterity_cap"]
      base + (cap.present? ? [ dexterity, cap.to_i ].min : dexterity)
    end
    effects = derived_feature_effects(level:, subclass_name:)
    armor *= effects.fetch("armor_multiplier", 1).to_i
    armor += value_for_stat(values, effects["armor_stat_addition"]) if effects["armor_stat_addition"].present?
    armor
  end

  def mana_max_for(stat_values: nil, level: self.level)
    return nil if character_class.blank?

    resource_rules = character_class.resource_rules.to_h
    return nil if level.to_i < resource_rules.fetch("max_start_level", 1).to_i

    formula = resource_rules.fetch("max_formula", "").to_s.split(";").first.to_s
    match = formula.match(/(?:mana\s+)?(STR|DEX|INT|WIL)\s*(?:\*\s*(\d+))?\s*\+\s*LVL/i)
    return nil unless match

    stat = { "STR" => "strength", "DEX" => "dexterity", "INT" => "intelligence", "WIL" => "will" }.fetch(match[1].upcase)
    multiplier = match[2].to_i.nonzero? || 1
    (value_for_stat(stat_values || current_stat_values, stat) * multiplier) + level.to_i
  end

  def derived_resource_tracks_for(stat_values:, level: self.level, feature_choices: recorded_feature_choices, subclass_name: self.subclass_name)
    class_pools = Array(character_class&.resource_rules.to_h["pools"])
    ancestry_pools = Rules::NimbleCatalog.ancestry_resource_pools_for(ancestry&.name)
    pools = class_pools + ancestry_pools
    choice_effects = Rules::NimbleCatalog.feature_choice_effects_for(character_class&.name, feature_choices)
    derived_resource_modifiers = derived_feature_effects(level:, subclass_name:).fetch("resource_max_modifiers", {})
    choice_resource_modifiers = choice_effects.fetch("resource_max_modifiers", {})
    resource_keys = derived_resource_modifiers.keys | choice_resource_modifiers.keys
    resource_max_modifiers = resource_keys.index_with do |key|
      derived_resource_modifiers.fetch(key, 0).to_i + choice_resource_modifiers.fetch(key, 0).to_i
    end

    pools.filter_map do |pool|
      pool = pool.to_h
      next if level.to_i < pool.fetch("start_level", 1).to_i

      maximum = resource_track_max_from(pool, stat_values, level)
      maximum += resource_max_modifiers.fetch(pool.fetch("key"), 0).to_i if maximum.present?
      die = resource_die_for(pool["die_by_level"], level)
      initial_current = pool.key?("initial_current") ? pool["initial_current"].to_i : maximum.to_i

      {
        "key" => pool.fetch("key"),
        "name" => pool.fetch("name"),
        "formula" => pool["max_formula"],
        "max" => maximum,
        "current" => initial_current,
        "initial_current" => initial_current,
        "die" => die,
        "reset" => pool["reset"],
        "reset_events" => Array(pool["reset_events"]),
        "source_ref" => pool["source_ref"],
        "source_quote" => pool["source_quote"]
      }.compact
    end
  end

  def derived_resource_values_for(stat_values:, level: self.level, feature_choices: recorded_feature_choices, subclass_name: self.subclass_name)
    rules = character_class&.resource_rules.to_h
    formula = rules["max_formula"].presence || rules["formula"].presence
    tracks = derived_resource_tracks_for(
      stat_values: stat_values,
      level: level,
      feature_choices: feature_choices,
      subclass_name: subclass_name
    )
    legacy_values = resource_tracker_values_for(tracks)
    die = tracks.find { |track| track["die"].present? }&.fetch("die")

    {
      name: rules["name"],
      formula: formula,
      die: die || resource_die_for(rules["die_by_level"], level),
      max_mana: legacy_values.fetch(:max_mana),
      current_mana: legacy_values.fetch(:current_mana),
      max_resource: legacy_values.fetch(:max_resource),
      current_resource: legacy_values.fetch(:current_resource),
      resource_tracks: tracks
    }
  end

  def resource_tracker_values_for(tracks)
    tracks = Array(tracks)
    mana = tracks.find { |track| track.to_h["key"] == "mana" }
    resource = tracks.reject { |track| track.to_h["key"] == "mana" }.find { |track| track.to_h["max"].present? }

    {
      max_mana: mana&.[]("max"),
      current_mana: mana&.[]("current"),
      max_resource: resource&.[]("max"),
      current_resource: resource&.[]("current")
    }
  end

  def preserved_resource_tracks(new_tracks, preserved_tracker_state = nil)
    preserved_tracker_state ||= {
      resource_tracks: trait_set&.resource_tracks,
      current_mana: trait_set&.current_mana,
      previous_max_mana: trait_set&.max_mana,
      current_resource: trait_set&.current_resource,
      previous_max_resource: trait_set&.max_resource
    }
    previous_tracks = Array(preserved_tracker_state[:resource_tracks]).index_by { |track| track.to_h["key"] }
    legacy_resource_available = previous_tracks.empty?
    used_legacy_resource = false

    Array(new_tracks).map do |track|
      track = track.to_h.stringify_keys
      previous = previous_tracks[track["key"]]
      current = previous&.[]("current")
      previous_max = previous&.[]("max")
      if current.nil? && legacy_resource_available && track["key"] == "mana"
        current = preserved_tracker_state[:current_mana]
        previous_max = preserved_tracker_state[:previous_max_mana]
      elsif current.nil? && legacy_resource_available && !used_legacy_resource
        current = preserved_tracker_state[:current_resource]
        previous_max = preserved_tracker_state[:previous_max_resource]
        used_legacy_resource = true
      end

      current = track["current"] if current.nil?
      track.merge("current" => preserved_or_clamped_value(current, previous_max, track["max"]))
    end
  end

  def normalized_resource_tracks(submitted_tracks, current_wounds: nil)
    submitted = Array(submitted_tracks).map { |track| track.to_h.stringify_keys }.index_by { |track| track["key"] }
    gained_wound = current_wounds.present? && current_wounds.to_i > (trait_set&.current_wounds || 0).to_i
    baseline = if gained_wound
      derived_resource_tracks_for(stat_values: current_stat_values).index_by { |track| track.fetch("key") }
    else
      {}
    end

    Array(trait_set&.resource_tracks).map do |track|
      track = track.to_h.stringify_keys
      input = submitted[track["key"]]
      current = input.present? ? input["current"].to_i : track["current"]
      reset_events = Array(track["reset_events"].presence || baseline.dig(track["key"], "reset_events"))
      if gained_wound && reset_events.include?("wound_gained")
        current = track["max"]
      end

      track.merge("current" => current, "reset_events" => reset_events)
    end
  end

  def creation_issues
    issues = []
    issues << rule_issue("Choose a class before finalizing.", "Chapter 2, Class Rules", "Every hero has one class.") if character_class.blank?
    issues << rule_issue("Choose an ancestry before finalizing.", "Chapter 2, Ancestry Rules", "Every hero has one ancestry.") if ancestry.blank?
    issues << rule_issue("Choose a background before finalizing.", "Chapter 2, Backgrounds", "Every hero has one background.") if background.blank?
    issues << rule_issue("Choose a stat array before finalizing.", "Chapter 3, Character Creation", "Choose Standard, Balanced, or Min-Max and assign it to your class stats.") if stat_array.blank?
    if character_class.present? && stat_array.present? && !stat_assignments_valid?
      issues << rule_issue(
        "Place each value from the #{stat_array.humanize} array exactly once.",
        "Chapter 3, Character Creation",
        "Choose a stat array, then place its four values across your four stats."
      )
    end
    issues << rule_issue("Start new characters at level 1.", "Chapter 3, Character Creation", "A starting character begins at level 1.") if level.present? && level != 1 && !playable? && !level_up_in_progress?

    if character_class&.spell_schools&.include?("choice") && spell_school_choice.blank?
      issues << rule_issue(
        "Choose one additional spell school for #{character_class.name}.",
        "Heroes 2.0.1, p. 55",
        "You know Wind cantrips and one other school of your choice."
      )
    end

    valid_additional_schools = %w[Fire Ice Lightning Wind Radiant Necrotic]
    if character_class&.spell_schools&.include?("choice") && spell_school_choice.present? && !valid_additional_schools.include?(spell_school_choice)
      issues << rule_issue(
        "#{spell_school_choice} is not a legal additional spell school for #{character_class.name}.",
        "Heroes 2.0.1, p. 55",
        "Songweaver chooses one additional school alongside Wind."
      )
    end

    if subclass_name.present? && !subclass_options.include?(subclass_name)
      issues << rule_issue(
        "#{subclass_name} is not a legal subclass for #{character_class&.name || 'this class'}.",
        character_class&.source_reference || "Heroes 2.0.1, Subclasses",
        "Choose a subclass listed for the character's class at level 3."
      )
    elsif level.to_i >= 3 && character_class.present? && subclass_options.present? && subclass_name.blank?
      issues << rule_issue(
        "Choose a #{character_class.name} subclass before playing at level #{level}.",
        character_class.source_reference,
        "At level 3, choose a subclass for your class."
      )
    end

    self.spells.each do |spell|
      next if spell.available_to?(self)

      citation = spell.citation
      issues << rule_issue(
        "#{spell.name} is not available to this class at level #{level}.",
        citation.fetch(:source_ref),
        citation.fetch(:quote) || "Spell access is determined by class school and unlocked tier."
      )
    end if character_class.present?

    if background.present? && !background.satisfied_by?(projected_or_current_stat_set)
      issues << rule_issue(
        "#{background.name} requires #{background.prerequisite_stat.to_s.upcase} ≤ #{background.prerequisite_max}.",
        "Chapter 2, Backgrounds",
        "This background has a creation-time stat prerequisite."
      )
    end

    validate_starting_background_spell_choice(issues)

    if stat_set.present?
      invalid_skills = SKILL_NAMES.select { |skill| skill_value(skill).to_i < skill_initial_value(skill) }
      invalid_skills.each do |skill|
        issues << rule_issue(
          "#{skill.humanize} cannot be lower than its governing stat.",
          "Chapter 3, Skills",
          "A skill starts at its governing stat bonus."
        )
      end

      if skill_points_spent > skill_point_budget
        issues << rule_issue(
          "You have spent #{skill_points_spent} skill points, but only #{skill_point_budget} are available.",
          "Chapter 3, Skills",
          "New heroes receive 4 extra skill points; each later level adds 1."
        )
      elsif skill_points_spent < skill_point_budget
        issues << rule_issue(
          "Spend #{skill_point_budget - skill_points_spent} more skill points before finalizing.",
          "Chapter 3, Skills",
          "A starting hero must distribute all 4 extra skill points."
        )
      end
    end

    issues
  end

  def creation_explanations
    creation_issues.map { |issue| issue.merge(type: "blocked", context: rules_context_label) }
  end

  def finalize_creation!
    raise ActiveRecord::RecordInvalid, self unless legal_for_creation?

    transaction do
      update!(status: "playable")
      sync_granted_utility_spells!
      record_revision!(event_type: "finalized", summary: "Character finalized as playable", from_level: level, to_level: level)
    end
  end

  def level_up_eligible?
    playable? && level.to_i < 20 && creation_issues.empty?
  end

  def skill_point_budget
    4 + [ level.to_i - 1, 0 ].max
  end

  def skill_points_spent
    return 0 unless skill_set

    SKILL_NAMES.sum { |skill| [ skill_value(skill).to_i - skill_initial_value(skill), 0 ].max }
  end

  def skill_initial_value(skill)
    return 0 unless stat_set

    stat_set.public_send(SKILL_TO_STAT.fetch(skill)).to_i + derived_modifier_for(:all_skills_bonus) + ancestry&.skill_bonus_for(skill).to_i + background&.skill_bonus_for(skill).to_i
  end

  def skill_value(skill)
    skill_set&.public_send(skill)
  end

  def stat_value(stat)
    stat_set&.public_send(stat).to_i
  end

  def stat_assignment_values
    values = stat_assignments.to_h.stringify_keys
    return {} unless values.keys.intersection(STAT_NAMES).length == STAT_NAMES.length

    values.slice(*STAT_NAMES).transform_values(&:to_i)
  end

  def stat_assignment_value(stat)
    stat_assignment_values[stat.to_s]
  end

  def stat_assignments_valid?
    return true if stat_array.blank? || character_class.blank? || stat_assignments.blank?

    expected_values = STAT_ARRAYS[stat_array]
    return false if expected_values.blank?

    stat_assignment_values.size == STAT_NAMES.size && stat_assignment_values.values.sort == Array(expected_values).sort
  end

  def stat_increase_type_for(level)
    return character_class.stat_increase_type_for(level) if character_class.present?

    STAT_INCREASE_LEVELS.each do |type, levels|
      return type if levels.include?(level.to_i)
    end

    nil
  end

  def stat_increase_options_for(level)
    type = stat_increase_type_for(level)
    character_class&.stat_options_for(type) || (type == "any_two" ? STAT_NAMES : [])
  end

  def snapshot_payload
    {
      "character" => attributes.slice(
        "name", "race", "nimble_class", "level", "subclass_name", "legacy_background_text", "description", "languages", "spell_school_choice", "starting_equipment", "stat_assignments", "feature_choices", "spell_choices",
        "status", "conditions", "inventory", "game_notes", "stat_array"
      ),
      "rules" => {
        "class" => character_class&.name,
        "ancestry" => ancestry&.name,
        "background" => background&.name,
        "saves" => {
          "bonus" => character_class&.save_bonus_stat,
          "penalty" => character_class&.save_penalty_stat
        },
        "ruleset" => rules_context_label
      },
      "progression" => {
        "class_features" => progression_features_through,
        "subclass_features" => subclass_progression_features_through,
        "feature_choices" => feature_choice_entries_through,
        "spell_choices" => spell_choice_entries_through,
        "derived_effects" => derived_feature_effects
      },
      "stats" => stat_set&.attributes&.slice("strength", "dexterity", "intelligence", "will"),
      "skills" => skill_set&.attributes&.slice(*SKILL_NAMES),
      "traits" => trait_set&.attributes&.slice(
        "initiative", "speed", "hit_die", "current_hit_dice", "max_hit_dice", "current_actions", "max_actions",
        "armor", "save_dc", "max_mana", "current_mana", "resource_name", "resource_formula", "resource_die", "max_resource", "current_resource", "resource_tracks",
        "temp_hp", "current_hp", "max_hp", "current_wounds", "max_wounds", "inventory_slots"
      ),
      "spells" => spells.order(:name).pluck(:name)
    }
  end

  def record_revision!(event_type:, summary:, from_level: nil, to_level: nil)
    character_revisions.create!(
      event_type: event_type,
      summary: summary,
      from_level: from_level,
      to_level: to_level,
      snapshot: snapshot_payload
    )
  end

  def derived_modifier_for(attribute, level: self.level, subclass_name: self.subclass_name)
    origin_modifier = [ ancestry, background ].compact.sum do |origin|
      origin.respond_to?(attribute) ? origin.public_send(attribute).to_i : 0
    end
    origin_modifier + derived_feature_effects(level:, subclass_name:).fetch(attribute.to_s, 0).to_i
  end

  def ensure_defaults
    build_default_stat_set if not stat_set
    build_default_skill_set if not skill_set
    build_default_trait_set if not trait_set
  end

  private
    def record_initial_revision
      record_revision!(event_type: "created", summary: "Character created", from_level: level, to_level: level)
    end

    def playable_state_is_legal
      creation_issues.each do |issue|
        errors.add(:base, issue.fetch(:message))
      end
    end

    def assign_default_ruleset
      return if ruleset_version.present? || !defined?(RulesetVersion) || !RulesetVersion.table_exists?

      self.ruleset_version = RulesetVersion.active.order(:id).first || RulesetVersion.create!(
        name: "Nimble", version: "v2.0.1", source_reference: "Nimble Core Rules, Heroes, and Gamemaster's Guide", published_at: Date.new(2026, 7, 1)
      )
    end

    def should_sync_derived_values?
      new_record? || character_class_id_changed? || ancestry_id_changed? || background_id_changed? || stat_array_changed?
    end

    def sync_derived_values
      if (stat_array_changed? || character_class_id_changed?) && !will_save_change_to_stat_assignments?
        self.stat_assignments = nil
      end
      if stat_array.present? && character_class.present? && stat_assignments.blank?
        self.stat_assignments = default_stat_assignments
      end

      if character_class.present? && stat_array.present?
        assign_attributes_to_stat_set(projected_stat_values)
      end

      assign_attributes_to_skill_set if stat_set.present?

      assign_attributes_to_trait_set if trait_set.blank? || canonical_choices_changed?

      self.languages = derived_languages if languages.blank? || canonical_choices_changed?
      if character_class.present?
        self.starting_equipment = starting_equipment_summary if starting_equipment.blank?
        self.inventory = starting_equipment_summary if inventory.blank?
      end
    end

    def canonical_choices_changed?
      character_class_id_changed? || ancestry_id_changed? || background_id_changed? || stat_array_changed?
    end

    def assign_attributes_to_stat_set(values)
      target = stat_set || build_stat_set
      target.assign_attributes(values)
    end

    def assign_attributes_to_skill_set
      target = skill_set || build_skill_set
      SKILL_NAMES.each do |skill|
        baseline = stat_set.public_send(SKILL_TO_STAT.fetch(skill)).to_i + derived_modifier_for(:all_skills_bonus) + ancestry&.skill_bonus_for(skill).to_i + background&.skill_bonus_for(skill).to_i
        submitted_value = target.public_send(skill)
        target.public_send("#{skill}=", submitted_value.nil? ? baseline : [ submitted_value.to_i, baseline ].max)
      end
    end

    def assign_attributes_to_trait_set
      target = trait_set || build_trait_set
      preserved_tracker_state = if persisted? && target.persisted?
        {
          current_hp: target.current_hp,
          previous_max_hp: target.max_hp,
          current_wounds: target.current_wounds,
          previous_max_wounds: target.max_wounds,
          current_hit_dice: target.current_hit_dice,
          previous_max_hit_dice: target.max_hit_dice,
          current_actions: target.current_actions,
          previous_max_actions: target.max_actions,
          current_mana: target.current_mana,
          previous_max_mana: target.max_mana,
          current_resource: target.current_resource,
          previous_max_resource: target.max_resource,
          resource_tracks: target.resource_tracks,
          temp_hp: target.temp_hp
        }
      end
      level_value = level.to_i.positive? ? level.to_i : 1
      subclass_for_effects = self.subclass_name
      starting_hp = (character_class&.starting_hp || 10) + derived_modifier_for(:max_hp_modifier, level: level_value, subclass_name: subclass_for_effects)
      max_hit_dice = level_value + derived_modifier_for(:max_hit_dice_modifier, level: level_value, subclass_name: subclass_for_effects)
      max_wounds = DEFAULT_MAX_WOUNDS + derived_modifier_for(:max_wounds_modifier, level: level_value, subclass_name: subclass_for_effects)
      stat_values = current_stat_values
      resource_values = derived_resource_values_for(stat_values: stat_values, level: level_value, subclass_name: subclass_for_effects)
      resource_tracks = resource_values.fetch(:resource_tracks)
      resource_tracks = preserved_resource_tracks(resource_tracks, preserved_tracker_state) if preserved_tracker_state
      legacy_resource_values = resource_tracker_values_for(resource_tracks)
      target.assign_attributes(
        initiative: initiative_for(stat_values, level: level_value, subclass_name: subclass_for_effects),
        speed: speed_for(level: level_value, subclass_name: subclass_for_effects),
        hit_die: hit_die_for(level: level_value, subclass_name: subclass_for_effects),
        current_hit_dice: max_hit_dice,
        max_hit_dice: max_hit_dice,
        current_actions: 3,
        max_actions: 3,
        armor: armor_for(stat_values, level: level_value, subclass_name: subclass_for_effects).to_i + derived_modifier_for(:armor_modifier, level: level_value, subclass_name: subclass_for_effects),
        save_dc: save_dc_for(stat_values),
        max_mana: legacy_resource_values.fetch(:max_mana),
        current_mana: legacy_resource_values.fetch(:current_mana),
        resource_name: resource_values.fetch(:name),
        resource_formula: resource_values.fetch(:formula),
        resource_die: resource_values.fetch(:die),
        max_resource: legacy_resource_values.fetch(:max_resource),
        current_resource: legacy_resource_values.fetch(:current_resource),
        resource_tracks: resource_tracks,
        inventory_slots: BASE_INVENTORY_SLOTS + stat_set&.strength.to_i,
        temp_hp: 0,
        current_hp: starting_hp,
        max_hp: starting_hp,
        current_wounds: 0,
        max_wounds: max_wounds
      )

      if preserved_tracker_state
        target.current_hp = preserved_or_clamped_value(
          preserved_tracker_state[:current_hp], preserved_tracker_state[:previous_max_hp], target.max_hp
        )
        target.current_wounds = preserved_or_clamped_value(
          preserved_tracker_state[:current_wounds], preserved_tracker_state[:previous_max_wounds], target.max_wounds
        )
        target.current_hit_dice = preserved_or_clamped_value(
          preserved_tracker_state[:current_hit_dice], preserved_tracker_state[:previous_max_hit_dice], target.max_hit_dice
        )
        target.current_actions = preserved_or_clamped_value(
          preserved_tracker_state[:current_actions], preserved_tracker_state[:previous_max_actions], target.max_actions
        )
        target.current_mana = preserved_or_clamped_value(
          preserved_tracker_state[:current_mana], preserved_tracker_state[:previous_max_mana], target.max_mana
        )
        target.current_resource = preserved_or_clamped_value(
          preserved_tracker_state[:current_resource], preserved_tracker_state[:previous_max_resource], target.max_resource
        )
        target.temp_hp = preserved_tracker_state[:temp_hp]
      end
    end

    def preserved_or_clamped_value(current, previous_max, new_max)
      return nil if current.nil?
      return new_max if previous_max.present? && current >= previous_max

      [ current, new_max ].compact.min
    end

    def derived_languages
      languages = [ "Common" ]
      languages.concat(ancestry.language_names) if ancestry.present? && stat_value("intelligence") >= 0
      languages.concat(background.language_names) if background.present? && stat_value("intelligence") >= 0
      (stat_value("intelligence").positive? ? stat_value("intelligence") : 0).times do |index|
        languages << [ "Dwarvish", "Elvish", "Goblin", "Infernal", "Thieves' Cant", "Celestial", "Draconic", "Primordial", "Deep Speak" ][index] || "Additional language"
      end
      languages.uniq.join(", ")
    end

  private
    def current_stat_values
      {
        "strength" => stat_set&.strength.to_i,
        "dexterity" => stat_set&.dexterity.to_i,
        "intelligence" => stat_set&.intelligence.to_i,
        "will" => stat_set&.will.to_i
      }
    end

    def value_for_stat(stat_values, stat)
      stat_values[stat.to_s] || stat_values[stat.to_sym] || 0
    end

    def resource_max_from_formula(formula, stat_values)
      return nil if formula.blank?

      return character_class.key_stats.map { |stat| value_for_stat(stat_values, stat) }.max.to_i if formula.match?(/\bKEY\b/i)

      match = formula.match(/\b(STR|DEX|INT|WIL)\b/i)
      return nil unless match

      stat = { "STR" => "strength", "DEX" => "dexterity", "INT" => "intelligence", "WIL" => "will" }.fetch(match[1].upcase)
      value_for_stat(stat_values, stat)
    end

    def resource_track_max_from(pool, stat_values, level)
      max_by_level = pool["max_by_level"].to_h.select { |unlock_level, _maximum| level.to_i >= unlock_level.to_i }
      return max_by_level.max_by { |unlock_level, _maximum| unlock_level.to_i }&.last&.to_i if max_by_level.present?

      formula = pool["max_formula"].to_s
      return nil if formula.blank?
      return formula.to_i if formula.match?(/\A\d+\z/)

      multiplier_match = formula.match(/\A\s*(\d+)\s*\*\s*LVL\b/i)
      return multiplier_match[1].to_i * level.to_i if multiplier_match

      return key_stat_max(stat_values) if formula.match?(/\bKEY\b/i)

      stat_match = formula.match(/\b(STR|DEX|INT|WIL)\b/i)
      return nil unless stat_match

      stat = { "STR" => "strength", "DEX" => "dexterity", "INT" => "intelligence", "WIL" => "will" }.fetch(stat_match[1].upcase)
      multiplier = (formula.match(/\b#{stat_match[1]}\s*\*\s*(\d+)/i)&.[](1) || formula.match(/(\d+)\s*\*\s*#{stat_match[1]}\b/i)&.[](1)).to_i.nonzero? || 1
      value = value_for_stat(stat_values, stat) * multiplier
      value += level.to_i if formula.match?(/\+\s*LVL/i)
      value
    end

    def key_stat_max(stat_values)
      character_class.key_stats.map { |stat| value_for_stat(stat_values, stat) }.max.to_i
    end

    def resource_die_for(die_by_level, level)
      entries = die_by_level.to_h.select { |unlock_level, _die| level.to_i >= unlock_level.to_i }
      entries.max_by { |unlock_level, _die| unlock_level.to_i }&.last
    end

    def projected_or_current_stat_set
      stat_set || build_projected_stat_set
    end

    def rule_issue(message, source_ref, quote)
      { message: message, source_ref: source_ref, quote: quote }
    end

    def utility_spell_options(schools)
      Spell.where(tier: -1, school: Array(schools)).order(:school, :name).pluck(:name)
    end

    def utility_spell_options_from_any_school
      Spell.where(tier: -1).order(:school, :name).pluck(:name)
    end

    def resource_tracks_after_safe_rest
      baseline = derived_resource_tracks_for(stat_values: current_stat_values).index_by { |track| track.fetch("key") }

      Array(trait_set.resource_tracks).map do |track|
        track = track.to_h.stringify_keys
        reset_events = Array(track["reset_events"].presence || baseline.dig(track.fetch("key"), "reset_events"))
        refreshed_value = if (reset_events & %w[safe_rest healed_to_max_hp]).any?
          track["max"]
        elsif reset_events.include?("encounter_end")
          track["initial_current"] || baseline.dig(track.fetch("key"), "initial_current") || baseline.dig(track.fetch("key"), "current")
        end

        track = track.merge("reset_events" => reset_events) if reset_events.present?
        refreshed_value.nil? ? track : track.merge("current" => refreshed_value.to_i)
      end
    end

    def starting_background_spell_choice_pool
      definition = Rules::NimbleCatalog.background_spell_choice_for(background&.name)
      return if definition.blank?

      definition.merge(
        "name" => background.name,
        "level" => 1,
        "count" => definition.fetch("count", 1).to_i,
        "options" => utility_spell_options_from_any_school
      )
    end

    def validate_starting_background_spell_choice(issues)
      pool = starting_background_spell_choice_pool
      selections = spell_choice_selections_for("Academy Dropout", 1)

      if pool.blank?
        if selections.any?
          issues << rule_issue(
            "Academy Dropout's Utility Spell choice is not available for this background.",
            "Core Rules 2.0.1, p. 28",
            "Academy Dropout grants one Utility Spell only when it is the chosen background."
          )
        end
        return
      end

      if selections.length != pool.fetch("count")
        issues << rule_issue(
          "Academy Dropout requires one Utility Spell choice.",
          pool.fetch("source_ref"),
          pool.fetch("source_quote")
        )
      end

      invalid_selections = selections - Array(pool.fetch("options"))
      invalid_selections.each do |selection|
        issues << rule_issue(
          "#{selection} is not a Utility Spell option for Academy Dropout.",
          pool.fetch("source_ref"),
          pool.fetch("source_quote")
        )
      end
    end

    def build_projected_stat_set
      return nil unless character_class.present? && stat_array.present?

      StatSet.new(projected_stat_values)
    end

    def projected_stat_values
      assigned_values = stat_assignment_values
      return assigned_values.symbolize_keys if assigned_values.size == STAT_NAMES.size

      values = Array(STAT_ARRAYS[stat_array]).sort.reverse
      keys = character_class.key_stats
      secondaries = character_class.secondary_stats

      { keys[0] => values[0], keys[1] => values[1],
        secondaries[0] => values[2], secondaries[1] => values[3] }.symbolize_keys
    end

    def default_stat_assignments
      values = Array(STAT_ARRAYS[stat_array]).sort.reverse
      keys = character_class.key_stats
      secondaries = character_class.secondary_stats

      { keys[0] => values[0], keys[1] => values[1],
        secondaries[0] => values[2], secondaries[1] => values[3] }.stringify_keys
    end

    def stat_assignments_match_array
      return if stat_array.blank? || character_class.blank? || stat_assignments.blank?
      return if stat_assignments_valid?

      errors.add(:stat_assignments, "must use each value from the selected stat array exactly once")
    end

    def build_default_stat_set
      if character_class.present? && stat_array.present?
        build_stat_set(projected_stat_values)
      else
        build_stat_set strength: 0,
                        dexterity: 0,
                        intelligence: 0,
                        will: 0
      end
    end

    def build_default_skill_set
      all_skills_bonus = derived_modifier_for(:all_skills_bonus)
      skill_values = SKILL_NAMES.index_with do |skill|
        all_skills_bonus + ancestry&.skill_bonus_for(skill).to_i + background&.skill_bonus_for(skill).to_i
      end

      build_skill_set(**skill_values)
    end

    def build_default_trait_set
      level_value = level.to_i.positive? ? level.to_i : 1
      subclass_for_effects = self.subclass_name
      hit_die = hit_die_for(level: level_value, subclass_name: subclass_for_effects)
      starting_hp = (character_class&.starting_hp || 10) + derived_modifier_for(:max_hp_modifier, level: level_value, subclass_name: subclass_for_effects)
      stat_values = current_stat_values
      initiative = initiative_for(stat_values, level: level_value, subclass_name: subclass_for_effects)
      speed = speed_for(level: level_value, subclass_name: subclass_for_effects)
      max_hit_dice = level_value + derived_modifier_for(:max_hit_dice_modifier, level: level_value, subclass_name: subclass_for_effects)
      armor = armor_for(stat_values, level: level_value, subclass_name: subclass_for_effects).to_i + derived_modifier_for(:armor_modifier, level: level_value, subclass_name: subclass_for_effects)
      max_wounds = DEFAULT_MAX_WOUNDS + derived_modifier_for(:max_wounds_modifier, level: level_value, subclass_name: subclass_for_effects)
      resource_values = derived_resource_values_for(stat_values: stat_values, level: level_value, subclass_name: subclass_for_effects)

      build_trait_set initiative:        initiative,
                      speed:             speed,
                      hit_die:           hit_die,
                      current_hit_dice:  max_hit_dice,
                      max_hit_dice:      max_hit_dice,
                      current_actions:   3,
                      max_actions:       3,
                      armor:             armor,
                      save_dc:           save_dc_for(stat_values),
                      max_mana:          resource_values.fetch(:max_mana),
                      current_mana:      resource_values.fetch(:current_mana),
                      resource_name:     resource_values.fetch(:name),
                      resource_formula:  resource_values.fetch(:formula),
                      resource_die:      resource_values.fetch(:die),
                      max_resource:      resource_values.fetch(:max_resource),
                      current_resource:  resource_values.fetch(:current_resource),
                      resource_tracks:   resource_values.fetch(:resource_tracks),
                      inventory_slots:   BASE_INVENTORY_SLOTS + stat_values.fetch("strength"),
                      temp_hp:           0,
                      current_hp:        starting_hp,
                      max_hp:            starting_hp,
                      current_wounds:    0,
                      max_wounds:        max_wounds
    end
end
