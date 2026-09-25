class Character < ApplicationRecord
  serialize :stat_assignments, coder: JSON
  serialize :feature_choices, coder: JSON
  serialize :spell_choices, coder: JSON
  serialize :subclass_choices, coder: JSON
  serialize :language_choices, coder: JSON
  serialize :feature_language_choices, coder: JSON

  BASE_SPEED = Rules::NimbleCatalog.derived_values.fetch("base_speed").to_i
  DEFAULT_MAX_ACTIONS = Rules::NimbleCatalog.derived_values.fetch("default_max_actions").to_i
  DEFAULT_MAX_WOUNDS = Rules::NimbleCatalog.derived_values.fetch("default_max_wounds").to_i
  BASE_INVENTORY_SLOTS = Rules::NimbleCatalog.derived_values.fetch("base_inventory_slots").to_i
  MAX_LEVEL = Rules::NimbleCatalog.derived_values.fetch("max_level").to_i
  STARTING_EQUIPMENT_CHOICES = %w[class_gear starting_gold].freeze

  # Nimble creation-time stat arrays (02-rules-canon.md S-1 #1). The builder
  # recommends placing the highest values in Key Stats, but the rules allow
  # the player to place each array value freely.
  STAT_ARRAYS = Rules::NimbleCatalog.stat_arrays.transform_values(&:freeze).freeze
  STAT_NAMES = Rules::NimbleCatalog.stats.keys.freeze
  SKILL_TO_STAT = Rules::NimbleCatalog.skills.freeze
  SKILL_NAMES = SKILL_TO_STAT.keys.freeze

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
  has_many :story_subclass_changes, dependent: :destroy
  has_many :character_revisions, dependent: :destroy
  has_many :level_ups, dependent: :destroy
  has_many :character_shares, dependent: :destroy
  has_many :campaigns, through: :character_shares
  has_many :inventory_items, dependent: :destroy

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
  validates :starting_equipment_choice, inclusion: { in: STARTING_EQUIPMENT_CHOICES }
  validates :current_gold, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :level, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_LEVEL }, allow_nil: true
  validate :stat_assignments_match_array
  validate :playable_state_is_legal, if: :playable?
  validate :starting_equipment_choice_only_changes_while_draft
  validate :level_changes_require_level_up_transition
  validate :story_based_subclass_requires_approved_change

  before_create :ensure_defaults
  before_validation :assign_default_ruleset
  before_validation :sync_derived_values, if: :should_sync_derived_values?
  before_validation :sync_languages, if: :should_sync_languages?
  before_validation :sync_starting_equipment, if: :should_sync_starting_equipment?
  after_create :sync_starting_gear_inventory
  after_update :sync_starting_gear_inventory, if: :starting_gear_loadout_changed?
  after_create :record_initial_revision

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

  def imported_character?
    character_revisions.where(event_type: "imported").exists?
  end

  def known_spell_schools
    schools = character_class&.spell_schools || []
    schools = schools.reject { |school| school == "choice" }
    schools << spell_school_choice if character_class&.spell_school_choice_rule.present? && spell_school_choice.present?
    schools.uniq
  end

  def language_choice_count(stat_values = current_stat_values)
    [ value_for_stat(stat_values, "intelligence").to_i, 0 ].max * Rules::NimbleCatalog.language_rules.fetch("intelligence_choices_per_point").to_i
  end

  def language_origin_grants(stat_values = current_stat_values)
    minimum_intelligence = Rules::NimbleCatalog.language_rules.fetch("ancestry_grant_minimum_intelligence").to_i
    return [] if value_for_stat(stat_values, "intelligence").to_i < minimum_intelligence

    [ ancestry&.language_names, background&.language_names ].flatten.compact.map(&:to_s).uniq
  end

  def language_choice_options_for(stat_values = current_stat_values, excluding: language_choices, level: self.level, feature_choices: recorded_feature_choices, feature_language_choices: self.feature_language_choices)
    language_rules = Rules::NimbleCatalog.language_rules
    automatically_known = [
      language_rules.fetch("default_language"),
      *language_origin_grants(stat_values),
      *Rules::NimbleCatalog.class_language_grants_for(character_class&.name, level),
      *known_feature_languages(feature_choices, feature_language_choices)
    ]
    Array(language_rules.fetch("languages")).map(&:to_s) - automatically_known - Array(excluding).compact_blank.map(&:to_s)
  end

  def known_language_names(stat_values = current_stat_values, choices: language_choices, level: self.level, feature_choices: recorded_feature_choices, feature_language_choices: self.feature_language_choices)
    language_rules = Rules::NimbleCatalog.language_rules
    grants = language_origin_grants(stat_values)
    class_grants = Rules::NimbleCatalog.class_language_grants_for(character_class&.name, level)
    selections = Array(choices).compact_blank.map(&:to_s) & language_choice_options_for(
      stat_values,
      excluding: [],
      level:,
      feature_choices:,
      feature_language_choices: []
    )
    feature_grants = known_feature_languages(feature_choices, feature_language_choices)
    ([ language_rules.fetch("default_language"), *grants, *class_grants, *selections, *feature_grants ]).uniq
  end

  def remaining_language_choice_count(stat_values = current_stat_values, choices: language_choices)
    [ language_choice_count(stat_values) - Array(choices).length, 0 ].max
  end

  def language_issues_for(stat_values:, choices: language_choices, feature_choices: recorded_feature_choices, feature_selections: feature_language_choices, level: self.level)
    language_selection_issues(stat_values, choices:, feature_choices:, feature_selections:, level:)
  end

  def with_approved_story_subclass_change(from_subclass:, to_subclass:, story_note:, campaign:, approved_by:)
    previous_approval = @approved_story_subclass_change
    @approved_story_subclass_change = {
      from_subclass: from_subclass.to_s,
      to_subclass: to_subclass.to_s,
      story_note: story_note.to_s,
      campaign_id: campaign.id,
      approved_by_account_id: approved_by.id
    }
    yield
  ensure
    @approved_story_subclass_change = previous_approval
  end

  def subclass_options
    character_class&.subclass_options || []
  end

  def known_subclass_options
    character_class&.known_subclass_options || []
  end

  def available_spells
    spells = Spell.order(:tier, :name)
    return Spell.none if character_class.blank?

    spells.select { |spell| spell.available_to?(self) }
  end

  def starting_equipment_summary
    return "#{starting_gold_for_level} gp" if starting_equipment_choice == "starting_gold"

    character_class&.starting_gear&.join(", ")
  end

  def starting_gold_for_level(level_value = level)
    rules = Rules::NimbleCatalog.starting_equipment_rules
    per_level = rules.fetch("gold_per_level").to_i
    per_level * [ level_value.to_i, 1 ].max
  end

  def gold_inventory_slots
    gold_per_slot = Rules::NimbleCatalog.starting_equipment_rules.fetch("gold_per_inventory_slot").to_i
    return 0 unless current_gold.to_i.positive? && gold_per_slot.positive?

    (current_gold.to_i + gold_per_slot - 1) / gold_per_slot
  end

  def inventory_slots_used
    inventory_items.sum(:slots) + gold_inventory_slots
  end

  def starting_gear_inventory_slots
    starting_gear_inventory_items.sum(:slots)
  end

  def starting_gear_inventory_items
    inventory_items.where(starting_gear: true).order(:id)
  end

  def inventory_slots_capacity
    (trait_set&.inventory_slots).to_i
  end

  def inventory_slots_remaining
    inventory_slots_capacity - inventory_slots_used
  end

  def derived_condition_entries
    return [] unless trait_set && trait_set.current_hp.present? && trait_set.max_hp.to_i.positive?

    rules = Rules::NimbleCatalog.condition_tracking
    rules.fetch("derived_conditions").select do |condition|
      case condition.fetch("predicate")
      when "at_or_below_half_hit_points"
        trait_set.current_hp.to_i * 2 <= trait_set.max_hp.to_i
      when "zero_hit_points"
        trait_set.current_hp.to_i.zero?
      when "any_wounds"
        trait_set.current_wounds.to_i.positive?
      else
        raise ArgumentError, "Unknown derived condition predicate: #{condition.fetch('predicate')}"
      end
    end.map do |condition|
      entry = condition.merge("source_ref" => condition.fetch("source_ref", rules.fetch("source_ref")))
      next entry unless condition.fetch("name") == "Dying"

      action_limit = Rules::NimbleCatalog.dying_action_limit_for(character_class&.name, level)
      entry.merge(
        "actions_limited_to" => action_limit.fetch("actions_limited_to"),
        "effects_source_ref" => action_limit.fetch("source_ref"),
        "effects_source_quote" => action_limit.fetch("source_quote")
      )
    end
  end

  def progression_features_through(level = self.level)
    return [] if character_class.blank?

    level = level.presence || 1

    1.upto([ level.to_i, MAX_LEVEL ].min).flat_map do |feature_level|
      progression_features_for(feature_level).map do |name|
        { level: feature_level, name: name }
      end
    end
  end

  def progression_features_for(level, subclass_name: self.subclass_name)
    features = character_class&.features_for(level).to_a
    replaced_features = Rules::NimbleCatalog.story_subclass_replaced_progression_features_for(character_class&.name, subclass_name)
    return features if replaced_features.empty?

    features.reject do |name|
      replaced_features.any? { |replaced| name == replaced || name.start_with?("#{replaced} ", "#{replaced} (") }
    end
  end

  def subclass_progression_features_through(level = self.level)
    return [] if character_class.blank? || subclass_name.blank?

    level = level.presence || 1

    1.upto([ level.to_i, MAX_LEVEL ].min).flat_map do |feature_level|
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

  def feature_choice_pools_for(level, subclass_name: self.subclass_name, selected_feature_choices: recorded_feature_choices)
    pools = character_class&.feature_choice_pools_for(level).to_a
    selected_choices = selected_feature_choices.to_h.stringify_keys.transform_values { |selections| Array(selections).map(&:to_s) }
    pools.reject! do |pool|
      requirement = pool.fetch("requires_feature_choice", {})
      requirement.present? && !selected_choices.fetch(requirement.fetch("pool"), []).include?(requirement.fetch("option"))
    end
    story_pools = Rules::NimbleCatalog.story_subclass_feature_choice_pools_for(character_class&.name, subclass_name, level)
    replaced_pools = Rules::NimbleCatalog.story_subclass_replaced_feature_choice_pools_for(character_class&.name, subclass_name)
    pools.reject! { |pool| replaced_pools.include?(pool.fetch("name")) }

    story_pools.each do |story_pool|
      story_pool = story_pool.merge("options" => story_subclass_feature_options(story_pool))
      base_pool = pools.find { |pool| pool.fetch("name") == story_pool.fetch("name") }
      story_options = Array(story_pool.fetch("options", []))
      if base_pool
        base_options = story_pool.fetch("replace_existing_options", false) ? [] : Array(base_pool.fetch("options", []))
        base_pool.merge!(
          "options" => (base_options + story_options).uniq,
          "story_options" => story_options - Array(base_pool.fetch("repeatable_options", [])),
          "story_source_ref" => story_pool.fetch("source_ref"),
          "story_source_quote" => story_pool.fetch("source_quote"),
          "story_choice_kind" => story_pool["kind"],
          "story_choice_groups" => story_pool.fetch("choice_groups", []),
          "story_option_sources" => story_pool.fetch("option_sources", [])
        )
      else
        pools << story_pool.merge(
          "story_options" => story_options,
          "story_source_ref" => story_pool.fetch("source_ref"),
          "story_source_quote" => story_pool.fetch("source_quote"),
          "story_choice_kind" => story_pool["kind"],
          "story_choice_groups" => story_pool.fetch("choice_groups", []),
          "story_option_sources" => story_pool.fetch("option_sources", [])
        )
      end
    end

    pools
  end

  def story_subclass_feature_options(pool)
    sources = Array(pool.fetch("option_sources", []))
    return Array(pool.fetch("options", [])) if sources.empty?

    sources.flat_map do |source|
      story_subclass_feature_option_source_options(source).map do |option|
        "#{source.fetch('prefix', '')}#{option}"
      end
    end.uniq
  end

  def story_subclass_feature_option_source_options(source)
    case source.fetch("type")
    when "choice_pool"
      Rules::NimbleCatalog.choice_pool_for(source.fetch("class_name"), source.fetch("pool_name"))
        .to_h.fetch(source.fetch("option_field", "options"), [])
    when "spell_catalog"
      minimum_tier = source.fetch("min_tier", 0).to_i
      maximum_tier = source.fetch("max_tier", 9).to_i
      Spell.where(tier: minimum_tier..maximum_tier).order(:name).pluck(:name)
    else
      raise ArgumentError, "Unsupported story subclass choice source: #{source.fetch('type')}"
    end
  end

  def normalize_story_subclass_feature_selections(pool, selections)
    kind = pool.fetch("story_choice_kind", nil)
    return selections unless %w[arcane_command_order_or_spell arcane_command_combat_ability].include?(kind)

    sources = Array(pool.fetch("story_option_sources", []))
    selections.filter_map do |selection|
      next selection if Array(pool.fetch("options", [])).include?(selection)

      source = sources.find do |candidate|
        story_subclass_feature_option_source_options(candidate).include?(selection)
      end
      next unless source

      "#{source.fetch('prefix', '')}#{selection}"
    end
  end

  def story_subclass_feature_choice_pools_through(subclass_name:, level: self.level, ledger: feature_choice_ledger)
    1.upto([ level.to_i, MAX_LEVEL ].min).flat_map do |choice_level|
      feature_choice_pools_for(choice_level, subclass_name:).select { |pool| pool["story_source_ref"].present? }.map do |pool|
        pool.merge(
          "level" => choice_level,
          "selected" => normalize_story_subclass_feature_selections(
            pool,
            feature_choice_selections_for(pool.fetch("name"), choice_level, ledger)
          )
        )
      end
    end
  end

  def story_subclass_companion_rule(subclass_name = self.subclass_name)
    Rules::NimbleCatalog.story_subclass_companion_rule_for(character_class&.name, subclass_name)
  end

  def story_subclass_companion_ability_entries(level: self.level, subclass_name: self.subclass_name)
    rule = story_subclass_companion_rule(subclass_name)
    companion = subclass_choices.to_h.stringify_keys.fetch("companion", {}).to_h.stringify_keys
    return [] if rule.blank? || companion.blank?

    size = companion.fetch("size", "")
    selected_choices = feature_choice_selections_for("Thrill of the Hunt", 2)
    tracks = Array(trait_set&.resource_tracks).index_by { |track| track.to_h["key"] }

    Rules::NimbleCatalog.story_subclass_companion_abilities_for(character_class&.name, subclass_name).filter_map do |name, ability|
      next if ability["requires_choice"] && !selected_choices.include?(name)

      variant = ability.to_h.fetch("variants", {}).fetch(size, nil)
      next if variant.blank? || level.to_i < variant.fetch("minimum_level", 1).to_i

      track = tracks[variant["track_key"]]
      maximum = uses_per_encounter_for(variant, level)
      uses_per_round = level_value_for(variant.fetch("uses_per_round_by_level", {}), level)
      {
        name:,
        effect: level_effect_for(variant, level),
        action_cost: variant["action_cost"],
        cost: variant["cost"],
        uses: track.present? ? "#{track.fetch('current')} / #{maximum} per encounter" : nil,
        uses_per_round: uses_per_round.present? ? "#{uses_per_round} per round" : nil,
        source_ref: rule.fetch("source_ref"),
        source_quote: variant["source_quote"] || ability["source_quote"] || rule.fetch("source_quote")
      }.compact
    end
  end

  def story_subclass_initiative_feature_entries
    Rules::NimbleCatalog.story_subclass_initiative_features_for(character_class&.name, subclass_name)
      .select do |feature|
        unlock_level = Rules::NimbleCatalog.story_subclass_feature_unlock_level_for(
          character_class&.name,
          subclass_name,
          feature.fetch("name")
        )
        unlock_level.present? && level.to_i >= unlock_level
      end
  end

  def initiative_resource_grant
    initiative_resource_grants.first
  end

  def initiative_resource_grants
    Rules::NimbleCatalog.initiative_resource_grants_for(character_class&.name, subclass_name, level, feature_choices: recorded_feature_choices)
  end

  def initiative_optional_action_entries
    story_subclass_initiative_feature_entries.filter_map do |feature|
      action = feature["initiative_action"]
      next if action.blank?

      action.merge(
        "feature_name" => feature.fetch("name"),
        "effect" => feature.fetch("effect"),
        "source_ref" => feature.fetch("source_ref"),
        "source_quote" => feature.fetch("source_quote")
      )
    end
  end

  def story_subclass_initiative_trigger_entries
    story_subclass_initiative_feature_entries.filter_map do |feature|
      trigger = feature["initiative_trigger"]
      next if trigger.blank?

      trigger.merge(
        "feature_name" => feature.fetch("name"),
        "effect" => feature.fetch("effect"),
        "source_ref" => feature.fetch("source_ref"),
        "source_quote" => feature.fetch("source_quote")
      )
    end
  end

  def initiative_resource_dice_count(grant = initiative_resource_grant)
    grant.to_h.fetch("amount_dice_by_level", {})
      .select { |unlock_level, _count| level.to_i >= unlock_level.to_i }
      .max_by { |unlock_level, _count| unlock_level.to_i }
      &.last
      &.to_i || 0
  end

  def initiative_resource_die_sides(grant = initiative_resource_grant)
    grant.to_h.fetch("amount_die", 0).to_i
  end

  def initiative_resource_reroll_rule(grant = initiative_resource_grant)
    rule = grant.to_h["reroll_rule"]
    return if rule.blank?
    return unless subclass_name == rule.fetch("subclass_name")
    return if level.to_i < rule.fetch("minimum_level").to_i

    rule
  end

  def initiative_resource_amount(grant = initiative_resource_grant, resource_tracks: Array(trait_set&.resource_tracks), dice_rolls: nil)
    return 0 if grant.blank?
    amount = if grant.fetch("amount", nil).to_s == "maximum"
      track = resource_tracks.map(&:to_h).find do |resource|
        resource.fetch("key") == grant.fetch("resource_key")
      end
      return 0 if track.blank?

      [ track.fetch("max").to_i - track.fetch("current").to_i, 0 ].max
    elsif grant["amount_stat"].present?
      stat_value(grant.fetch("amount_stat")) + grant.fetch("amount_bonus_by_level", {}).sum do |unlock_level, bonus|
        level.to_i >= unlock_level.to_i ? bonus.to_i : 0
      end
    else
      grant.fetch("amount").to_i
    end

    if dice_rolls
      required_rolls = initiative_resource_dice_count(grant)
      raise ArgumentError, "#{grant.fetch('feature_label')} requires exactly #{required_rolls} die result#{'s' unless required_rolls == 1}." unless dice_rolls.length == required_rolls

      amount += dice_rolls.sum(&:to_i)
    end

    if grant["amount_from_spent_resource"].present?
      spent_track = resource_tracks.map(&:to_h).find do |resource|
        resource.fetch("key") == grant.fetch("amount_from_spent_resource")
      end
      return 0 if spent_track.blank? || spent_track["max"].blank?

      spent_uses = [ spent_track.fetch("max").to_i - spent_track.fetch("current").to_i, 0 ].max
      already_refunded = resource_tracks.map(&:to_h).find do |resource|
        resource.fetch("key") == grant.fetch("resource_key")
      end&.fetch("current", 0).to_i
      amount = [ amount, [ spent_uses - already_refunded, 0 ].max ].min
    end

    amount
  end

  def wound_prevention_rule
    Rules::NimbleCatalog.wound_prevention_rule_for(character_class&.name, level)
  end

  def unyielding_resolve_available?
    rule = wound_prevention_rule
    return false if rule.blank? || encounter_started_at.blank?

    uses = character_revisions.where(event_type: "unyielding_resolve")
      .where("created_at >= ?", encounter_started_at)
      .count
    uses < rule.fetch("uses_per_encounter", 1).to_i
  end

  def story_subclass_feature_note_entries(level: self.level)
    Rules::NimbleCatalog.story_subclass_feature_notes_for(character_class&.name, subclass_name)
      .select { |note| level.to_i >= note.fetch("unlock_level").to_i }
  end

  def story_subclass_feature_unlocked?(feature_name)
    story_subclass_feature_note_entries.any? { |note| note.fetch("name") == feature_name.to_s }
  end

  def story_subclass_weapon_entry
    weapon = Rules::NimbleCatalog.story_subclass_weapon_rules_for(character_class&.name, subclass_name).fetch("Bonescythe", nil)
    return if weapon.blank?

    dice_interval = weapon.fetch("additional_die_every_levels").to_i
    dice_increase = weapon.fetch("additional_dice_per_interval").to_i
    dice_count = weapon.fetch("base_damage_dice").to_i + (level.to_i / dice_interval * dice_increase)
    dexterity = stat_value(weapon.fetch("bonus_damage_stat"))
    {
      name: "Bonescythe",
      damage_dice: "#{dice_count}#{weapon.fetch('damage_die')}",
      additional_dice_per_interval: dice_increase,
      damage_dice_interval: dice_interval,
      damage_effect: "#{weapon.fetch('damage_type').capitalize} damage plus DEX (#{dexterity}) #{weapon.fetch('bonus_damage_type')} damage per die",
      reach: weapon.fetch("reach"),
      action_cost: weapon.fetch("action_cost"),
      invocation_carryover_note: weapon.fetch("invocation_carryover_note"),
      summoned: bonescythe_summoned?,
      source_ref: weapon.fetch("source_ref"),
      source_quote: weapon.fetch("source_quote")
    }
  end

  def story_subclass_restricted_spell_names
    Rules::NimbleCatalog.story_subclass_spell_restrictions_for(character_class&.name, subclass_name)
  end

  def story_subclass_empowered_order_entries
    empowered_orders = Rules::NimbleCatalog.story_subclass_empowered_orders_for(character_class&.name, subclass_name)
    return [] if empowered_orders.empty?

    selected_orders = recorded_feature_choices.values.flatten.map do |selection|
      selection.start_with?("Order: ") ? selection.delete_prefix("Order: ") : selection
    end.uniq

    selected_orders.filter_map do |name|
      rule = empowered_orders[name]
      next if rule.blank?

      {
        name:,
        arcane_name: rule.fetch("arcane_name"),
        effect: rule.fetch("effect"),
        source_ref: rule.fetch("source_ref"),
        source_quote: rule.fetch("source_quote")
      }
    end
  end

  def feature_choice_pools_through(level = self.level)
    return [] if character_class.blank?

    level = level.presence || 1
    ledger = feature_choice_ledger

    1.upto([ level.to_i, MAX_LEVEL ].min).flat_map do |feature_level|
      feature_choice_pools_for(feature_level).map do |pool|
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

      source_refs = [ pool.fetch("source_ref") ]
      source_refs << pool.fetch("story_source_ref") if (Array(pool.fetch("story_options", [])) & pool.fetch("selected")).any?

      {
        level: pool.fetch("level"),
        name: pool.fetch("name"),
        selected: pool.fetch("selected"),
        selected_labels: pool.fetch("option_labels", {}).slice(*pool.fetch("selected")),
        selected_descriptions: pool.fetch("option_descriptions", {}).slice(*pool.fetch("selected")),
        source_refs: source_refs.uniq
      }
    end
  end

  def feature_choice_selections_for(pool_name, level, ledger = feature_choice_ledger)
    selections_by_level = ledger.fetch(pool_name.to_s, {})
    return selections_by_level.fetch(level.to_i.to_s, []) if selections_by_level.key?(level.to_i.to_s)
    return [] unless selections_by_level.key?("legacy")

    first_level = 1.upto([ level.to_i, MAX_LEVEL ].min).find do |candidate_level|
      feature_choice_pools_for(candidate_level).any? { |pool| pool.fetch("name") == pool_name.to_s }
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

  def spell_choice_pools_for(level, subclass_name: self.subclass_name)
    pools = character_class&.spell_choice_pools_for(level).to_a
    pools.concat(Rules::NimbleCatalog.story_subclass_spell_choice_pools_for(character_class&.name, subclass_name, level))
    background_pool = starting_background_spell_choice_pool
    if level.to_i == 1 && background_pool.present?
      pools << background_pool
    end

    pools.flat_map do |pool|
      case pool.fetch("kind")
      when "utility_school"
        [ pool.merge("options" => Array(pool.fetch("allowed_schools", []))) ]
      when "utility_spell"
        school_extensions = Rules::NimbleCatalog.story_subclass_spell_choice_school_extensions_for(character_class&.name, subclass_name)
        allowed_schools = (Array(pool.fetch("allowed_schools", [])) + school_extensions).uniq
        extended_pool = pool.merge("allowed_schools" => allowed_schools, "options" => utility_spell_options(allowed_schools))
        if school_extensions.any?
          extended_pool["story_source_ref"] = character_class.story_based_subclass_rule(subclass_name).fetch("source_ref")
        end
        [ extended_pool ]
      when "utility_spell_any"
        [ pool.merge("options" => utility_spell_options_from_any_school) ]
      when "spell_up_to_tier"
        tier = pool.fetch("max_tier").to_i
        [ pool.merge("options" => Spell.where(tier: 0..tier).order(:name).pluck(:name)) ]
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

  def story_subclass_spell_choice_pools_through(subclass_name:, level: self.level, ledger: spell_choice_ledger)
    1.upto([ level.to_i, MAX_LEVEL ].min).flat_map do |choice_level|
      spell_choice_pools_for(choice_level, subclass_name:).select { |pool| pool["story_subclass"].present? }.map do |pool|
        pool.merge(
          "selected" => spell_choice_selections_for(pool.fetch("name"), choice_level, ledger)
        )
      end
    end
  end

  def spell_choice_pools_through(level = self.level, ledger: spell_choice_ledger)
    level = level.presence || 1

    1.upto([ level.to_i, MAX_LEVEL ].min).flat_map do |choice_level|
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
        source_ref: pool.fetch("source_ref"),
        source_refs: [ pool.fetch("source_ref"), pool["story_source_ref"] ].compact.uniq
      }
    end
  end

  def spell_choice_selections_for(pool_name, level, ledger = spell_choice_ledger)
    selections_by_level = ledger.fetch(pool_name.to_s, {})
    return selections_by_level.fetch(level.to_i.to_s, []) if selections_by_level.key?(level.to_i.to_s)
    return [] unless selections_by_level.key?("legacy")

    first_level = 1.upto([ level.to_i, MAX_LEVEL ].min).find do |candidate_level|
      spell_choice_pools_for(candidate_level).any? { |pool| pool.fetch("name") == pool_name.to_s }
    end
    level.to_i == first_level ? selections_by_level.fetch("legacy") : []
  end

  def utility_spell_names(level: self.level, ledger: spell_choice_ledger)
    utility_schools = Spell.where(tier: -1).distinct.pluck(:school)
    utility_pools = spell_choice_pools_through(level, ledger: ledger).select do |pool|
      %w[utility_school utility_spell utility_spell_any utility_spell_each_known_school].include?(pool.fetch("kind"))
    end
    selections = utility_pools.flat_map do |pool|
      pool.fetch("selected") & Array(pool.fetch("options"))
    end
    auto_grants = character_class&.spell_auto_grants_for(level.to_i.positive? ? level : 1) || []
    auto_schools = auto_grants.include?("known") ? known_spell_schools : auto_grants
    schools = (selections & utility_schools) + auto_schools
    direct_names = selections - utility_schools

    Spell.where(tier: -1, school: schools).pluck(:name) + direct_names
  end

  def story_granted_spell_names(level: self.level)
    level_based_spells = spell_choice_pools_through(level).select do |pool|
      pool.fetch("kind") == "spell_up_to_tier"
    end.flat_map { |pool| pool.fetch("selected") & Array(pool.fetch("options")) }.uniq
    arcane_command_spells = recorded_feature_choices.values.flatten.filter_map do |selection|
      selection.delete_prefix("Spell: ") if selection.start_with?("Spell: ")
    end

    (level_based_spells + arcane_command_spells + story_subclass_granted_spell_names).uniq
  end

  def story_subclass_granted_spell_names
    Rules::NimbleCatalog.story_subclass_spell_grants_for(character_class&.name, subclass_name).map(&:to_s)
  end

  def sheet_spells
    rule_granted_names = granted_utility_spells.pluck(:name) + story_granted_spell_names
    sheet = Spell.where(id: (spells.ids + Spell.where(name: rule_granted_names).ids).uniq)
    restrictions = story_subclass_restricted_spell_names
    restrictions.any? ? sheet.where.not(name: restrictions) : sheet
  end

  def granted_utility_spells(level: self.level, ledger: spell_choice_ledger)
    Spell.where(name: utility_spell_names(level:, ledger:))
  end

  def sync_granted_utility_spells!(level: self.level, ledger: spell_choice_ledger)
    self.spells = (spells.to_a + granted_utility_spells(level:, ledger:).to_a).uniq
  end

  def take_safe_rest!
    rest_rules = Rules::NimbleCatalog.resting_rules.fetch("safe_rest")
    transaction do
      tracks = resource_tracks_after_safe_rest
      resource_values = resource_tracker_values_for(tracks)
      trait_set.update!(
        current_hp: rest_rules.fetch("recover_all_hit_points") ? trait_set.max_hp : trait_set.current_hp,
        current_hit_dice: rest_rules.fetch("recover_all_hit_dice") ? trait_set.max_hit_dice : trait_set.current_hit_dice,
        current_wounds: [ trait_set.current_wounds.to_i - rest_rules.fetch("wounds_healed").to_i, 0 ].max,
        temp_hp: rest_rules.fetch("temporary_hit_points_expire") ? 0 : trait_set.temp_hp,
        current_mana: resource_values.fetch(:current_mana) || trait_set.max_mana,
        current_resource: resource_values.fetch(:current_resource) || trait_set.max_resource,
        resource_tracks: tracks
      )
      update_columns(bonescythe_summoned: false, updated_at: Time.current) if bonescythe_summoned?
      update_columns(encounter_started_at: nil, updated_at: Time.current) if encounter_started_at.present?
      record_revision!(event_type: "safe_rest", summary: "Safe Rest completed", from_level: level, to_level: level)
    end
  end

  def begin_encounter!(dice_rolls: [], rerolls: [], feature_actions: {})
    with_lock do
      raise ArgumentError, "This encounter has already started. End it before recording another initiative roll." if encounter_started_at.present?
      tracks = Array(trait_set&.resource_tracks)
      grants = initiative_resource_grants
      action_summaries = initiative_feature_action_summaries(feature_actions)
      trigger_summaries = initiative_trigger_summaries
      if grants.empty? && action_summaries.empty? && initiative_optional_action_entries.empty? && trigger_summaries.empty?
        raise ArgumentError, "This character has no initiative-triggered feature to record."
      end
      required_dice = grants.sum { |grant| initiative_resource_dice_count(grant) }
      raw_dice_rolls = Array(dice_rolls)
      unless raw_dice_rolls.length == required_dice
        raise ArgumentError, "Enter exactly #{required_dice} die result#{'s' unless required_dice == 1} for the Initiative features being recorded."
      end
      dice_results = raw_dice_rolls.map { |result| parse_initiative_die_result(result) }
      raise ArgumentError, "Every Initiative die result must be a whole number." if dice_results.any?(&:nil?)

      raw_rerolls = Array(rerolls)
      raw_rerolls = Array.new(required_dice) if raw_rerolls.empty?
      unless raw_rerolls.length == required_dice
        raise ArgumentError, "Enter one optional reroll field for each Initiative die."
      end
      reroll_results = raw_rerolls.map do |result|
        result.to_s.blank? ? nil : parse_initiative_die_result(result)
      end
      if reroll_results.zip(raw_rerolls).any? { |parsed, raw| raw.to_s.present? && parsed.nil? }
        raise ArgumentError, "Every Initiative reroll must be a whole number."
      end

      dice_cursor = 0
      summaries = grants.map do |grant|
        track_key = grant.fetch("resource_key")
        track = tracks.find { |resource| resource.to_h.fetch("key") == track_key }
        raise ArgumentError, "#{grant.fetch('feature_label')} resource is unavailable on this sheet. #{grant.fetch('source_ref')}." unless track

        track = track.to_h
        dice_count = initiative_resource_dice_count(grant)
        grant_dice = dice_results.slice(dice_cursor, dice_count)
        grant_rerolls = reroll_results.slice(dice_cursor, dice_count)
        dice_cursor += dice_count
        die_sides = initiative_resource_die_sides(grant)
        if grant_dice.any? { |result| result < 1 || result > die_sides }
          raise ArgumentError, "#{grant.fetch('feature_label')} die results must each be between 1 and #{die_sides}."
        end
        if grant_rerolls.compact.any? { |result| result < 1 || result > die_sides }
          raise ArgumentError, "#{grant.fetch('feature_label')} rerolls must each be between 1 and #{die_sides}."
        end
        if grant_rerolls.zip(grant_dice).any? { |reroll, original| reroll.present? && original != 1 }
          raise ArgumentError, "#{grant.fetch('feature_label')} can only reroll a die that showed 1."
        end
        reroll_rule = initiative_resource_reroll_rule(grant)
        if reroll_rule.blank? && grant_rerolls.compact.any?
          raise ArgumentError, "#{grant.fetch('feature_label')} has no available die-reroll feature."
        end

        final_dice = grant_dice.zip(grant_rerolls).map { |original, reroll| reroll || original }
        requested_amount = [ initiative_resource_amount(grant, resource_tracks: tracks, dice_rolls: final_dice), 0 ].max
        available_capacity = track["max"].present? ? [ track.fetch("max").to_i - track.fetch("current").to_i, 0 ].max : nil
        gained_amount = available_capacity ? [ requested_amount, available_capacity ].min : requested_amount
        tracks = tracks.map do |resource|
          resource.to_h.fetch("key") == track_key ? resource.to_h.merge("current" => track.fetch("current").to_i + gained_amount) : resource
        end
        summary = grant.fetch("summary").gsub("%{amount}", gained_amount.to_s)
        if dice_count.positive?
          recorded_rolls = grant_dice.zip(grant_rerolls).map do |original, reroll|
            reroll.present? ? "#{original} → #{reroll}" : original.to_s
          end
          roll_note = "d#{die_sides} results: #{recorded_rolls.join(', ')}"
          roll_note += " (#{reroll_rule.fetch('feature_name')})" if grant_rerolls.compact.any?
          summary = "#{summary} (#{roll_note})"
        end
        summary
      end
      summary = (summaries + action_summaries + trigger_summaries).join("; ").presence || "Initiative recorded; no optional feature action taken"

      trait_set.update!(resource_tracks: tracks)
      update_columns(encounter_started_at: Time.current, updated_at: Time.current)
      record_revision!(event_type: "initiative_roll", summary:, from_level: level, to_level: level)
    end
  end

  def use_shadowpath_first_attack_advantage!
    with_lock do
      grant = initiative_resource_grants.find do |entry|
        entry.fetch("feature_name") == "Ambusher" && entry.fetch("resource_key") == "shadowpath_first_attack_advantage"
      end
      unless grant
        raise ArgumentError, "Ambusher's first-attack advantage requires a level 3 Shadowpath Hunter. Heroes 2.0.1, p. 28."
      end
      raise ArgumentError, "Record Initiative before spending Ambusher's first-attack advantage." if encounter_started_at.blank?

      tracks = Array(trait_set&.resource_tracks).map(&:to_h)
      track = tracks.find { |resource| resource.fetch("key") == grant.fetch("resource_key") }
      raise ArgumentError, "Ambusher's advantage tracker is unavailable. #{grant.fetch('source_ref')}." unless track
      raise ArgumentError, "Ambusher's first-attack advantage has already been used this encounter." unless track.fetch("current").to_i.positive?

      tracks = tracks.map do |resource|
        resource.fetch("key") == grant.fetch("resource_key") ? resource.merge("current" => resource.fetch("current").to_i - 1) : resource
      end
      trait_set.update!(resource_tracks: tracks)
      record_revision!(
        event_type: "shadowpath_first_attack_advantage",
        summary: "Applied Ambusher's advantage to the first attack this encounter (#{grant.fetch('source_ref')}); resolve the attack at the table",
        from_level: level,
        to_level: level
      )
    end
  end

  def summon_shadow_minion!
    rule = Rules::NimbleCatalog.class_resource_pool_for("Shadowmancer", "shadow_minions")
    raise ArgumentError, "Shadow Minion summon rules are unavailable. Heroes 2.0.1, p. 43." unless rule

    amount = rule.fetch("summon_amount").to_i
    action_cost = rule.fetch("summon_action_cost").to_i
    minions = "#{amount} Shadow Minion#{'s' unless amount == 1}"
    actions = "#{action_cost} action#{'s' unless action_cost == 1}"
    apply_shadow_minion_change!(amount, action_cost:, summary: "Summoned #{minions} (#{actions})")
  end

  def martyr_spawn!
    feature = require_reaver!("Martyr Spawn")
    amount = feature.fetch("shadow_minions_spent").to_i
    minions = "#{amount} Shadow Minion#{'s' unless amount == 1}"
    apply_shadow_minion_change!(-amount, summary: "Martyr Spawn sacrificed #{minions} to negate Defend damage", required_reaver_ability: "Martyr Spawn")
  end

  def use_shadow_exploit!(spell_name:)
    with_lock do
      require_reaver!("Shadow Exploit")
      spell = sheet_spells.find_by(name: spell_name.to_s)
      unless spell&.tier.to_i.positive? && spell.available_to?(self)
        raise ArgumentError, "Choose a known tiered spell you can cast. Heroes 2.0.1, p. 78."
      end

      tracks = Array(trait_set.resource_tracks).map(&:to_h)
      minion_track = tracks.find { |track| track.fetch("key") == "shadow_minions" }
      cost_track = tracks.find { |track| track.fetch("key") == "reaver_shadow_exploit_next_cost" }
      raise ArgumentError, "Reaver resource tracking is unavailable. Heroes 2.0.1, p. 78." unless minion_track && cost_track
      cost_rule = Rules::NimbleCatalog.story_subclass_resource_pool_for("Shadowmancer", "Reaver", "reaver_shadow_exploit_next_cost")
      raise ArgumentError, "Shadow Exploit cost rules are unavailable. Heroes 2.0.1, p. 78." unless cost_rule

      cost = cost_track.fetch("current").to_i
      increment = cost_rule.fetch("increment_per_cast").to_i
      if minion_track.fetch("current").to_i < cost
        raise ArgumentError, "Shadow Exploit costs #{cost} Shadow Minion#{'s' unless cost == 1}; you have #{minion_track.fetch('current')}."
      end

      tracks = tracks.map do |track|
        case track.fetch("key")
        when "shadow_minions"
          track.merge("current" => track.fetch("current").to_i - cost)
        when "reaver_shadow_exploit_next_cost"
          track.merge("current" => cost + increment)
        else
          track
        end
      end
      trait_set.update!(resource_tracks: tracks)
      highest_tier = character_class.spell_tier_for(level)
      record_revision!(
        event_type: "shadow_exploit",
        summary: "Cast #{spell.name} at Tier #{highest_tier} through Shadow Exploit; sacrificed #{cost} Shadow Minion#{'s' unless cost == 1}",
        from_level: level,
        to_level: level
      )
    end
  end

  def use_my_blood_my_power!(spell_name:)
    with_lock do
      feature = require_reaver!("My Blood, My Power")
      wounds_to_take = feature.fetch("wounds_to_take").to_i
      spell = sheet_spells.find_by(name: spell_name.to_s)
      unless spell&.tier.to_i.positive? && spell.available_to?(self)
        raise ArgumentError, "Choose a known tiered spell you can cast. Heroes 2.0.1, p. 78."
      end
      if trait_set.current_wounds.to_i + wounds_to_take > trait_set.max_wounds.to_i
        raise ArgumentError, "My Blood, My Power requires room to take #{wounds_to_take} Wound#{'s' unless wounds_to_take == 1}."
      end

      trait_set.update!(current_wounds: trait_set.current_wounds.to_i + wounds_to_take)
      highest_tier = character_class.spell_tier_for(level)
      record_revision!(
        event_type: "my_blood_my_power",
        summary: "Took #{wounds_to_take} Wound#{'s' unless wounds_to_take == 1} to cast #{spell.name} at Tier #{highest_tier} through My Blood, My Power",
        from_level: level,
        to_level: level
      )
    end
  end

  def summon_bonescythe!
    with_lock do
      require_reaver!("Hollow One")
      raise ArgumentError, "The Bonescythe is already summoned." if bonescythe_summoned?
      weapon = story_subclass_weapon_entry
      action_cost = weapon.fetch(:action_cost).to_i
      raise ArgumentError, "You need at least #{action_cost} action#{'s' unless action_cost == 1} to summon the Bonescythe." if trait_set.current_actions.to_i < action_cost

      trait_set.update!(current_actions: trait_set.current_actions.to_i - action_cost)
      update_columns(bonescythe_summoned: true, updated_at: Time.current)
      record_revision!(event_type: "weapon_summoned", summary: "Summoned Bonescythe (#{action_cost} action#{'s' unless action_cost == 1})", from_level: level, to_level: level)
    end
  end

  def mark_bonescythe_hit!(outcome: "hit")
    with_lock do
      require_reaver!("Hollow One")
      raise ArgumentError, "Summon the Bonescythe before recording a hit." unless bonescythe_summoned?

      hit_outcome = outcome.to_s
      unless %w[hit critical kill].include?(hit_outcome)
        raise ArgumentError, "Record a hit, critical hit, or kill."
      end

      summary = "Bonescythe hit recorded; weapon shattered"
      if story_subclass_feature_unlocked?("Reap") && %w[critical kill].include?(hit_outcome)
        reap = Rules::NimbleCatalog.story_subclass_feature_note_for("Shadowmancer", "Reaver", "Reap")
        amount = reap.fetch("shadow_minions_gained").to_i
        tracks = Array(trait_set.resource_tracks).map(&:to_h)
        minion_track = tracks.find { |track| track.fetch("key") == "shadow_minions" }
        raise ArgumentError, "Shadow Minions are unavailable on this sheet. Heroes 2.0.1, p. 43." unless minion_track

        current = minion_track.fetch("current").to_i
        maximum = minion_track.fetch("max").to_i
        gained = [ amount, maximum - current ].min
        if gained.positive?
          tracks = tracks.map do |track|
            track.fetch("key") == "shadow_minions" ? track.merge("current" => current + gained) : track
          end
          trait_set.update!(resource_tracks: tracks)
          minions = gained == 1 ? "a Shadow Minion" : "#{gained} Shadow Minions"
          summary += "; Reap summoned #{minions} after a Bonescythe #{hit_outcome == 'critical' ? 'critical hit' : 'kill'}"
        else
          summary += "; Reap could not add a minion because you are at your limit"
        end
      end

      update_columns(bonescythe_summoned: false, updated_at: Time.current)
      record_revision!(event_type: "weapon_shattered", summary:, from_level: level, to_level: level)
    end
  end

  def end_encounter!
    transaction do
      tracks = resource_tracks_after_encounter_end
      resource_values = resource_tracker_values_for(tracks)
      trait_set.update!(
        resource_tracks: tracks,
        current_mana: resource_values.fetch(:current_mana) || trait_set.current_mana,
        current_resource: resource_values.fetch(:current_resource) || trait_set.current_resource
      )
      update_columns(bonescythe_summoned: false, updated_at: Time.current) if bonescythe_summoned?
      update_columns(encounter_started_at: nil, updated_at: Time.current) if encounter_started_at.present?
      record_revision!(event_type: "encounter_end", summary: "Encounter ended; encounter-reset resources refreshed", from_level: level, to_level: level)
    end
  end

  def perform_field_rest!(mode:, hit_dice_count:, die_rolls: [], convert_healing_to_mana: false)
    mode = mode.to_s
    field_rest_rules = Rules::NimbleCatalog.resting_rules.fetch("field_rests")
    rest_rules = field_rest_rules[mode]
    source_ref = rest_rules&.fetch("source_ref") || Rules::NimbleCatalog.resting_rules.fetch("source_ref")
    count = Integer(hit_dice_count, exception: false)
    die_sides = hit_die_sides

    raise ArgumentError, "Choose a supported Field Rest. #{source_ref}." unless rest_rules
    raise ArgumentError, "Spend at least 1 Hit Die. #{source_ref}." unless count&.positive?
    if count > trait_set.current_hit_dice.to_i
      raise ArgumentError, "You have only #{trait_set.current_hit_dice} Hit Dice available. #{source_ref}."
    end
    raise ArgumentError, "This character has no usable Hit Die. #{source_ref}." unless die_sides&.positive?

    hit_dice_per_use = rest_rules["hit_dice_per_use"]&.to_i
    if hit_dice_per_use && count != hit_dice_per_use
      hit_dice_word = hit_dice_per_use == 1 ? "one" : hit_dice_per_use.to_s
      hit_die_unit = hit_dice_per_use == 1 ? "Hit Die" : "Hit Dice"
      raise ArgumentError, "Spend #{hit_dice_word} #{hit_die_unit} at a time for #{mode.humanize} so you can choose whether to continue. #{source_ref}."
    end

    rolls = Array(die_rolls).map { |roll| Integer(roll, exception: false) }
    hit_die_result = rest_rules.fetch("hit_die_result")
    if hit_die_result == "rolled"
      unless rolls.length == count && rolls.all? { |roll| roll&.between?(1, die_sides) }
        raise ArgumentError, "Enter exactly #{count} roll#{'s' if count != 1}, each from 1 to #{die_sides}. #{source_ref}."
      end
    end

    results = case hit_die_result
    when "rolled" then rolls
    when "maximum" then Array.new(count, die_sides)
    else raise ArgumentError, "Unsupported Hit Die result #{hit_die_result.inspect}. #{source_ref}."
    end
    stat_modifier = stat_value(rest_rules.fetch("stat_modifier")).to_i
    healing = case rest_rules.fetch("stat_modifier_application")
    when "each_hit_die" then results.sum { |roll| [ roll + stat_modifier, 0 ].max }
    else raise ArgumentError, "Unsupported Field Rest stat modifier application. #{source_ref}."
    end
    actual_healing = [ healing, trait_set.max_hp.to_i - trait_set.current_hp.to_i ].min
    new_hp = trait_set.current_hp.to_i + actual_healing
    field_rest_effects = Rules::NimbleCatalog.feature_choice_effects_for(character_class&.name, recorded_feature_choices).fetch("field_rest_effects", {})
    mana_conversion_rate = field_rest_effects.fetch("mana_conversion_hp_per_mana", 0).to_i
    mana_recovered = 0
    hp_healing_forgone = 0
    tracks = Array(trait_set.resource_tracks).map { |track| track.to_h.stringify_keys }
    if convert_healing_to_mana
      source_ref = Rules::NimbleCatalog.choice_pool_for(character_class&.name, "Epic Boon").to_h.fetch("source_ref")
      raise ArgumentError, "Epic Mana is required to convert healing into Mana. #{source_ref}." unless mana_conversion_rate.positive?

      mana_track = tracks.find { |track| track.to_h.fetch("key") == "mana" }
      raise ArgumentError, "This character has no Mana pool for Epic Mana conversion. #{source_ref}." unless mana_track

      missing_mana = mana_track.to_h.fetch("max").to_i - mana_track.to_h.fetch("current").to_i
      mana_recovered = [ actual_healing / mana_conversion_rate, missing_mana ].min
      raise ArgumentError, "This Field Rest cannot convert at least #{mana_conversion_rate} HP of healing into available Mana. #{source_ref}." unless mana_recovered.positive?

      hp_healing_forgone = actual_healing
      new_hp = trait_set.current_hp.to_i
    end
    tracks = normalized_resource_tracks(trait_set.resource_tracks, current_hp: new_hp)
    if mana_recovered.positive?
      tracks = tracks.map do |track|
        track.to_h.fetch("key") == "mana" ? track.to_h.merge("current" => track.to_h.fetch("current").to_i + mana_recovered) : track
      end
    end
    wound_threshold = field_rest_effects.fetch("wound_healing_threshold", 0).to_i
    wounds_recovered = if hit_die_result == "rolled" && wound_threshold.positive?
      [ results.count { |roll| roll >= wound_threshold }, trait_set.current_wounds.to_i ].min
    else
      0
    end
    resource_values = resource_tracker_values_for(tracks)

    transaction do
      trait_set.update!(
        current_hp: new_hp,
        current_wounds: trait_set.current_wounds.to_i - wounds_recovered,
        current_hit_dice: trait_set.current_hit_dice.to_i - count,
        current_mana: resource_values.fetch(:current_mana) || trait_set.current_mana,
        current_resource: resource_values.fetch(:current_resource) || trait_set.current_resource,
        resource_tracks: tracks
      )
      method_name = mode == "make_camp" ? "Make Camp" : "Catch Breath"
      mana_summary = mana_recovered.positive? ? "; forwent #{hp_healing_forgone} HP healing and recovered #{mana_recovered} Mana with Epic Mana (#{Rules::NimbleCatalog.choice_pool_for(character_class&.name, 'Epic Boon').fetch('source_ref')})" : ""
      wound_summary = wounds_recovered.positive? ? "; healed #{wounds_recovered} Wound#{'s' unless wounds_recovered == 1}" : ""
      record_revision!(
        event_type: "field_rest",
        summary: "#{method_name}: spent #{count} Hit Die#{'s' if count != 1}, recovered #{convert_healing_to_mana ? 0 : actual_healing} HP#{mana_summary}#{wound_summary}",
        from_level: level,
        to_level: level
      )
    end

    { mode:, hit_dice_spent: count, hp_recovered: convert_healing_to_mana ? 0 : actual_healing, hp_healing_forgone:, mana_recovered:, wounds_recovered: }
  end

  def derived_feature_effects(level: self.level, subclass_name: self.subclass_name)
    return {} if character_class.blank?

    Rules::NimbleCatalog.derived_effects_for(character_class.name, subclass_name, level.to_i.positive? ? level : 1)
  end

  def hit_die_for(level: self.level, subclass_name: self.subclass_name)
    derived_feature_effects(level:, subclass_name:).fetch("hit_die", character_class&.hit_die)
  end

  def max_hit_dice_for(level: self.level, subclass_name: self.subclass_name, feature_choices: recorded_feature_choices)
    progression = Rules::NimbleCatalog.hit_dice_progression
    level_one_maximum = progression.fetch("level_one_maximum").to_i
    increase_per_level = progression.fetch("increase_per_level").to_i
    level_based_maximum = level_one_maximum + [ level.to_i - 1, 0 ].max * increase_per_level
    level_based_maximum + derived_modifier_for(:max_hit_dice_modifier, level:, subclass_name:, feature_choices:)
  end

  def max_actions_for(level: self.level, subclass_name: self.subclass_name, feature_choices: recorded_feature_choices)
    DEFAULT_MAX_ACTIONS + derived_modifier_for(:max_actions_modifier, level:, subclass_name:, feature_choices:)
  end

  def hit_die_sides
    trait_set&.hit_die.to_s[/d(\d+)/i, 1]&.to_i
  end

  def initiative_for(stat_values = nil, level: self.level, subclass_name: self.subclass_name, feature_choices: recorded_feature_choices)
    values = stat_values || current_stat_values
    level_value = level.to_i.positive? ? level.to_i : 1
    effects = derived_feature_effects(level:, subclass_name:)
    gains_level_bonus = effects["initiative_level_bonus"] || (unarmored? && effects["unarmored_initiative_level_bonus"])
    level_bonus = gains_level_bonus ? level_value : 0
    initiative_stat = Rules::NimbleCatalog.stat_name_for_abbreviation(Rules::NimbleCatalog.derived_values.fetch("initiative_formula"))
    value_for_stat(values, initiative_stat) + derived_modifier_for(:initiative_modifier, level:, subclass_name:, feature_choices:) + level_bonus
  end

  def speed_for(level: self.level, subclass_name: self.subclass_name, feature_choices: recorded_feature_choices)
    effects = derived_feature_effects(level:, subclass_name:)
    unarmored_bonus = unarmored? ? effects.fetch("unarmored_speed_modifier", 0).to_i : 0
    BASE_SPEED + derived_modifier_for(:speed_modifier, level:, subclass_name:, feature_choices:) + unarmored_bonus
  end

  def unarmored?
    equipped_armor_profiles.none? { |item| item.fetch("rules").fetch("kind") == "armor" }
  end

  def save_dc_for(stat_values = nil)
    return nil if character_class.blank?

    values = stat_values || current_stat_values
    Rules::NimbleCatalog.derived_values.fetch("save_dc_base").to_i + character_class.key_stats.map { |stat| value_for_stat(values, stat) }.max.to_i
  end

  def equipped_armor_profiles
    inventory_profiles = if persisted?
      items = inventory_items.where(equipped: true).order(:id).to_a
      items.reject!(&:starting_gear?) if starting_gear_loadout_pending?
      items.filter_map do |item|
        armor_rules = Rules::NimbleCatalog.equipment_armor_item(item.name)
        next unless armor_rules

        { "name" => item.name, "rules" => armor_rules, "source_ref" => item.source_ref.presence || armor_rules.fetch("source_ref") }
      end
    else
      []
    end

    return inventory_profiles if persisted? && !starting_gear_loadout_pending?
    return inventory_profiles unless starting_equipment_choice == "class_gear" && character_class.present?

    starting_profiles = Rules::NimbleCatalog.starting_gear_inventory_items(character_class.name).filter_map do |item|
      armor_rules = Rules::NimbleCatalog.equipment_armor_item(item.fetch("name"))
      next unless armor_rules

      { "name" => item.fetch("name"), "rules" => armor_rules, "source_ref" => item.fetch("source_ref") }
    end

    inventory_profiles + starting_profiles
  end

  def armor_for(stat_values = nil, level: self.level, subclass_name: self.subclass_name, feature_choices: recorded_feature_choices)
    return nil if character_class.blank?

    values = stat_values || current_stat_values
    rules = character_class.armor_rules
    dexterity = value_for_stat(values, "dexterity")
    equipment = equipped_armor_profiles.select { |item| equipment_armor_requirement_met?(item.fetch("rules"), stat_values: values) }
    body_armor = equipment.select { |item| item.fetch("rules").fetch("kind") == "armor" }
      .max_by { |item| equipment_armor_value(item.fetch("rules"), stat_values: values) }
    shields = equipment.select { |item| item.fetch("rules").fetch("kind") == "shield" }

    armor = if body_armor
      equipment_armor_value(body_armor.fetch("rules"), stat_values: values)
    elsif rules.fetch("unarmored_formula", "dexterity") == "dexterity_plus_strength"
      dexterity + value_for_stat(values, "strength")
    else
      dexterity
    end
    per_shield_bonus = derived_modifier_for(:armor_per_shield_modifier, level:, subclass_name:, feature_choices:)
    armor += shields.sum { |item| item.fetch("rules").fetch("armor_value").to_i + per_shield_bonus }
    effects = derived_feature_effects(level:, subclass_name:)
    armor *= effects.fetch("armor_multiplier", 1).to_i unless body_armor
    armor += value_for_stat(values, effects["armor_stat_addition"]) if effects["armor_stat_addition"].present?
    armor
  end

  def equipment_armor_value(armor_rules, stat_values: current_stat_values)
    value = armor_rules.fetch("armor_value").to_i
    return value unless armor_rules.fetch("formula") == "dexterity"

    dexterity = value_for_stat(stat_values, "dexterity")
    cap = armor_rules["dexterity_cap"]
    value + (cap.present? ? [ dexterity, cap.to_i ].min : dexterity)
  end

  def equipment_armor_requirement_met?(armor_rules, stat_values: current_stat_values)
    requirement = armor_rules["strength_requirement"]
    requirement.blank? || value_for_stat(stat_values, "strength") >= requirement.to_i
  end

  def armor_proficient_with?(armor_rules)
    proficiencies = character_class&.armor_proficiencies || []
    proficiencies.include?("all") || proficiencies.include?(armor_rules.fetch("proficiency"))
  end

  def recalculate_equipment_derived_values!
    return unless persisted? && trait_set.present? && character_class.present?

    trait_set.update!(
      armor: armor_for + derived_modifier_for(:armor_modifier),
      initiative: initiative_for,
      speed: speed_for
    )
  end

  def mana_max_for(stat_values: nil, level: self.level, feature_choices: recorded_feature_choices)
    return nil if character_class.blank?

    derived_resource_tracks_for(
      stat_values: stat_values || current_stat_values,
      level:,
      feature_choices:
    ).find { |track| track.fetch("key") == "mana" }&.fetch("max")
  end

  def derived_resource_tracks_for(stat_values:, level: self.level, feature_choices: recorded_feature_choices, subclass_name: self.subclass_name)
    class_pools = Array(character_class&.resource_rules.to_h["pools"]).reject do |pool|
      pool.to_h["subclass_name"].present? && pool.to_h["subclass_name"] != subclass_name
    end
    replaced_pool_keys = Rules::NimbleCatalog.story_subclass_resource_pool_replacements_for(character_class&.name, subclass_name)
    class_pools = class_pools.reject { |pool| replaced_pool_keys.include?(pool.to_h["key"]) }
    ancestry_pools = Rules::NimbleCatalog.ancestry_resource_pools_for(ancestry&.name)
    story_pools = Rules::NimbleCatalog.story_subclass_resource_pools_for(character_class&.name, subclass_name)
    pools = class_pools + ancestry_pools + story_pools + story_subclass_companion_resource_pools(level:, subclass_name:)
    choice_effects = Rules::NimbleCatalog.feature_choice_effects_for(character_class&.name, feature_choices)
    choice_resource_pools = Rules::NimbleCatalog.feature_choice_resource_pools_for(character_class&.name, feature_choices)
    existing_pool_keys = pools.map { |pool| pool.to_h["key"] }
    pools += choice_resource_pools.reject { |pool| existing_pool_keys.include?(pool.fetch("key")) }
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
      maximum = [ maximum, pool.fetch("minimum_max").to_i ].max if maximum.present? && pool.key?("minimum_max")
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

  def story_subclass_companion_resource_pools(level:, subclass_name:)
    rule = story_subclass_companion_rule(subclass_name)
    companion = subclass_choices.to_h.stringify_keys.fetch("companion", {}).to_h.stringify_keys
    return [] if rule.blank? || companion.blank?

    selected_choices = feature_choice_selections_for("Thrill of the Hunt", 2)
    Rules::NimbleCatalog.story_subclass_companion_abilities_for(character_class&.name, subclass_name).filter_map do |name, ability|
      next if ability["requires_choice"] && !selected_choices.include?(name)

      variant = ability.to_h.fetch("variants", {}).fetch(companion.fetch("size", ""), nil)
      next if variant.blank? || variant["track_key"].blank?

      maximum = uses_per_encounter_for(variant, level)
      next if maximum.nil?

      {
        "key" => variant.fetch("track_key"),
        "name" => "#{name} · uses",
        "max_formula" => maximum.to_s,
        "initial_current" => maximum,
        "reset" => "Encounter ends",
        "reset_events" => [ "encounter_end" ],
        "source_ref" => rule.fetch("source_ref"),
        "source_quote" => variant["source_quote"] || ability["source_quote"] || rule.fetch("source_quote")
      }
    end
  end

  def uses_per_encounter_for(variant, level)
    value_for_level = level_value_for(variant.fetch("uses_by_level", {}), level)
    value_for_level&.to_i
  end

  def level_effect_for(variant, level)
    effect = level_value_for(variant.fetch("effect_by_level", {}), level)
    effect.presence || variant["effect"]
  end

  def level_value_for(values, level)
    values.to_h
      .select { |unlock_level, _value| level.to_i >= unlock_level.to_i }
      .max_by { |unlock_level, _value| unlock_level.to_i }
      &.last
  end

  def derived_resource_values_for(stat_values:, level: self.level, feature_choices: recorded_feature_choices, subclass_name: self.subclass_name)
    rules = character_class&.resource_rules.to_h
    formula = rules["max_formula"].presence || rules["formula"].presence
    replaced_pool_keys = Rules::NimbleCatalog.story_subclass_resource_pool_replacements_for(character_class&.name, subclass_name)
    resource_name = rules["name"]
    if replaced_pool_keys.present?
      active_class_pools = Array(rules["pools"]).reject do |pool|
        replaced_pool_keys.include?(pool.to_h["key"]) ||
          (pool.to_h["subclass_name"].present? && pool.to_h["subclass_name"] != subclass_name)
      end
      resource_name = active_class_pools.filter_map { |pool| pool.to_h["name"] }.join(" and ").presence
      formula = active_class_pools.filter_map { |pool| pool.to_h["max_formula"] }.join("; ").presence
    end
    tracks = derived_resource_tracks_for(
      stat_values: stat_values,
      level: level,
      feature_choices: feature_choices,
      subclass_name: subclass_name
    )
    legacy_values = resource_tracker_values_for(tracks)
    die = tracks.find { |track| track["die"].present? }&.fetch("die")

    {
      name: resource_name,
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

  def tracker_resource_event_grants_for(submitted_tracks)
    submitted = Array(submitted_tracks).map { |track| track.to_h.stringify_keys }.index_by { |track| track["key"] }
    previous = Array(trait_set&.resource_tracks).map { |track| track.to_h.stringify_keys }.index_by { |track| track["key"] }

    Rules::NimbleCatalog.resource_event_grants_for(
      "resource_increased",
      character_class&.name,
      level,
      subclass_name: subclass_name
    ).select do |grant|
      resource_key = grant.fetch("trigger_resource_key")
      previous_value = previous.dig(resource_key, "current")
      submitted_value = submitted.dig(resource_key, "current")
      previous_value.present? && submitted_value.present? && submitted_value.to_i > previous_value.to_i
    end
  end

  def normalized_resource_tracks(submitted_tracks, current_wounds: nil, current_hp: nil, gained_wounds: nil)
    submitted = Array(submitted_tracks).map { |track| track.to_h.stringify_keys }.index_by { |track| track["key"] }
    gained_wounds = [ current_wounds.to_i - (trait_set&.current_wounds || 0).to_i, 0 ].max if gained_wounds.nil? && current_wounds.present?
    gained_wounds = [ gained_wounds.to_i, 0 ].max
    gained_wound = gained_wounds.positive?
    healed_to_full = current_hp.present? && current_hp.to_i > (trait_set&.current_hp || 0).to_i && current_hp.to_i >= (trait_set&.max_hp || 0).to_i
    wound_grants = Rules::NimbleCatalog.resource_event_grants_for("wound_gained", character_class&.name, level, subclass_name: subclass_name)
      .each_with_object(Hash.new(0)) do |grant, amounts|
        amounts[grant.fetch("resource_key")] += grant.fetch("amount").to_i * gained_wounds
      end
    baseline = if gained_wound || healed_to_full
      derived_resource_tracks_for(stat_values: current_stat_values).index_by { |track| track.fetch("key") }
    else
      {}
    end

    Array(trait_set&.resource_tracks).map do |track|
      track = track.to_h.stringify_keys
      input = submitted[track["key"]]
      current = input.present? ? input["current"].to_i : track["current"]
      reset_events = Array(track["reset_events"].presence || baseline.dig(track["key"], "reset_events"))
      if (gained_wound && reset_events.include?("wound_gained")) || (healed_to_full && reset_events.include?("healed_to_max_hp"))
        current = track["max"]
      end
      if wound_grants[track["key"]].positive?
        current = current.to_i + wound_grants.fetch(track["key"])
        current = [ current, track["max"].to_i ].min if track["max"].present?
      end
      track.merge("current" => current, "reset_events" => reset_events)
    end
  end

  def creation_issues
    issues = []
    issues.concat(imported_progression_issues)
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
    if level.present? && level != 1 && !playable? && !level_up_in_progress? && !imported_character?
      issues << rule_issue("Start new characters at level 1.", "Chapter 3, Character Creation", "A starting character begins at level 1.")
    end
    issues.concat(language_selection_issues) if character_class.present? && stat_array.present? && stat_assignments_valid?

    spell_school_choice_rule = character_class&.spell_school_choice_rule
    if spell_school_choice_rule.present? && spell_school_choice.blank?
      issues << rule_issue(
        "Choose one additional spell school for #{character_class.name}.",
        spell_school_choice_rule.fetch("source_ref"),
        spell_school_choice_rule.fetch("source_quote")
      )
    end

    if spell_school_choice_rule.present? && spell_school_choice.present? && !Array(spell_school_choice_rule.fetch("allowed_schools", [])).include?(spell_school_choice)
      issues << rule_issue(
        "#{spell_school_choice} is not a legal additional spell school for #{character_class.name}.",
        spell_school_choice_rule.fetch("source_ref"),
        spell_school_choice_rule.fetch("source_quote")
      )
    end

    subclass_choice_level = character_class&.subclass_choice_level
    subclass_choice_quote = if subclass_choice_level.present?
      character_class.features_for(subclass_choice_level).find { |feature| feature == "Subclass choice" }
    end

    if subclass_name.present? && !known_subclass_options.include?(subclass_name)
      issues << rule_issue(
        "#{subclass_name} is not a legal subclass for #{character_class&.name || 'this class'} at its level #{subclass_choice_level} subclass choice.",
        character_class&.source_reference || "Heroes 2.0.1, Subclasses",
        subclass_choice_quote || "Choose a published subclass for this class."
      )
    elsif character_class.present? && subclass_options.present? && subclass_choice_level.blank?
      issues << rule_issue(
        "The rules catalog does not define when to choose a #{character_class.name} subclass.",
        "Nimble rules catalog · #{character_class.name} progression",
        "The published progression must include a Subclass choice feature."
      )
    elsif subclass_choice_level.present? && level.to_i >= subclass_choice_level && character_class.present? && subclass_options.present? && subclass_name.blank?
      issues << rule_issue(
        "Choose a #{character_class.name} subclass before playing at level #{level}.",
        character_class.source_reference,
        subclass_choice_quote
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
        skill_rules = Rules::NimbleCatalog.derived_values
        issues << rule_issue(
          "You have spent #{skill_points_spent} skill points, but only #{skill_point_budget} are available.",
          "Chapter 3, Skills",
          "Heroes receive #{skill_rules.fetch('skill_points_at_level_one')} extra skill points at level 1 and #{skill_rules.fetch('skill_points_per_level')} per later level."
        )
      elsif skill_points_spent < skill_point_budget
        issues << rule_issue(
          "Spend #{skill_point_budget - skill_points_spent} more skill points before finalizing.",
          "Chapter 3, Skills",
          "All #{skill_point_budget} available skill points must be allocated."
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
    playable? && level.to_i < MAX_LEVEL && creation_issues.empty?
  end

  def apply_level_up_transition!(new_level)
    @applying_level_up_transition = true
    update!(level: new_level, status: "playable")
  ensure
    @applying_level_up_transition = false
  end

  def skill_point_budget
    rules = Rules::NimbleCatalog.derived_values
    rules.fetch("skill_points_at_level_one").to_i + [ level.to_i - 1, 0 ].max * rules.fetch("skill_points_per_level").to_i
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
    character_class&.stat_increase_type_for(level)
  end

  def stat_increase_options_for(level)
    type = stat_increase_type_for(level)
    character_class&.stat_options_for(type) || (type == "any_two" ? STAT_NAMES : [])
  end

  def snapshot_payload
    {
      "character" => attributes.slice(
        "name", "race", "nimble_class", "level", "subclass_name", "subclass_choices", "legacy_background_text", "description", "languages", "language_choices", "feature_language_choices", "spell_school_choice", "starting_equipment", "starting_equipment_choice", "current_gold", "stat_assignments", "feature_choices", "spell_choices",
        "status", "conditions", "inventory", "game_notes", "stat_array", "encounter_started_at", "bonescythe_summoned"
      ),
      "inventory_items" => inventory_items.order(:id).map { |item| item.attributes.slice("name", "slots", "starting_gear", "source_ref", "catalog_slots", "equipped") },
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
        "initiative_features" => story_subclass_initiative_feature_entries,
        "empowered_orders" => story_subclass_empowered_order_entries,
        "derived_effects" => derived_feature_effects
      },
      "stats" => stat_set&.attributes&.slice("strength", "dexterity", "intelligence", "will"),
      "skills" => skill_set&.attributes&.slice(*SKILL_NAMES),
      "traits" => trait_set&.attributes&.slice(
        "initiative", "speed", "hit_die", "current_hit_dice", "max_hit_dice", "current_actions", "max_actions",
        "armor", "save_dc", "max_mana", "current_mana", "resource_name", "resource_formula", "resource_die", "max_resource", "current_resource", "resource_tracks",
        "temp_hp", "current_hp", "max_hp", "current_wounds", "max_wounds", "inventory_slots"
      ),
      "spells" => sheet_spells.order(:name).pluck(:name)
    }
  end

  def import_creation_snapshot
    finalized_revision = character_revisions.where(event_type: "finalized", to_level: 1).order(:created_at, :id).first
    return finalized_revision.snapshot if finalized_revision

    created_revision = character_revisions.where(event_type: "created").order(:created_at, :id).first
    if created_revision && created_revision.snapshot.to_h.dig("character", "level").to_i == 1
      return created_revision.snapshot
    end
    return snapshot_payload if level.to_i == 1

    nil
  end

  def interchange_level_ups
    level_ups.order(:to_level, :id).map do |level_up|
      {
        "from_level" => level_up.from_level,
        "to_level" => level_up.to_level,
        "status" => level_up.status,
        "hit_die_roll_one" => level_up.hit_die_roll_one,
        "hit_die_roll_two" => level_up.hit_die_roll_two,
        "skill_name" => level_up.skill_name,
        "skill_from" => level_up.skill_from,
        "stat_name" => level_up.stat_name,
        "second_stat_name" => level_up.second_stat_name,
        "subclass_name" => level_up.subclass_name,
        "feature_choices" => normalize_interchange_choices(level_up.feature_choices),
        "spell_choices" => normalize_interchange_choices(level_up.spell_choices),
        "language_choices" => Array(level_up.language_choices).compact_blank.map(&:to_s),
        "feature_language_choices" => level_up.feature_language_choices.to_h.stringify_keys.transform_values { |choices| Array(choices).compact_blank.map(&:to_s) },
        "notes" => level_up.notes
      }
    end
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

  def derived_modifier_for(attribute, level: self.level, subclass_name: self.subclass_name, feature_choices: recorded_feature_choices)
    origin_modifier = [ ancestry, background ].compact.sum do |origin|
      origin.respond_to?(attribute) ? origin.public_send(attribute).to_i : 0
    end
    choice_modifiers = Rules::NimbleCatalog.feature_choice_effects_for(character_class&.name, feature_choices).fetch("derived_modifiers", {})
    origin_modifier + derived_feature_effects(level:, subclass_name:).fetch(attribute.to_s, 0).to_i + choice_modifiers.fetch(attribute.to_s, 0).to_i
  end

  def ensure_defaults
    build_default_stat_set if not stat_set
    build_default_skill_set if not skill_set
    build_default_trait_set if not trait_set
  end

  private
    def normalize_interchange_choices(choices)
      choices.to_h.stringify_keys.transform_values do |selections|
        Array(selections).compact_blank.map(&:to_s)
      end
    end

    def require_reaver!(ability)
      feature = Rules::NimbleCatalog.story_subclass_feature_note_for("Shadowmancer", "Reaver", ability)
      return feature if character_class&.name == "Shadowmancer" && subclass_name == "Reaver" && story_subclass_feature_unlocked?(ability)

      minimum_level = feature&.fetch("unlock_level", 1).to_i
      raise ArgumentError, "#{ability} requires a level #{minimum_level} Shadowmancer Reaver. Heroes 2.0.1, p. 78."
    end

    def apply_shadow_minion_change!(amount, summary:, action_cost: 0, required_reaver_ability: nil)
      with_lock do
        if required_reaver_ability.present?
          require_reaver!(required_reaver_ability)
        elsif character_class&.name != "Shadowmancer"
          raise ArgumentError, "Only a Shadowmancer can summon Shadow Minions. Heroes 2.0.1, p. 43."
        end

        tracks = Array(trait_set&.resource_tracks).map(&:to_h)
        minion_track = tracks.find { |track| track.fetch("key") == "shadow_minions" }
        raise ArgumentError, "Shadow Minions are unavailable on this sheet. Heroes 2.0.1, p. 43." unless minion_track

        current = minion_track.fetch("current").to_i
        maximum = minion_track.fetch("max").to_i
        updated_count = current + amount.to_i
        raise ArgumentError, "You do not have a Shadow Minion to sacrifice." if updated_count.negative?
        raise ArgumentError, "You can control at most #{maximum} Shadow Minion#{'s' unless maximum == 1}." if updated_count > maximum

        updates = { resource_tracks: tracks.map do |track|
          track.fetch("key") == "shadow_minions" ? track.merge("current" => updated_count) : track
        end }
        if action_cost.positive?
          actions = trait_set.current_actions.to_i
          raise ArgumentError, "You need #{action_cost} action#{'s' unless action_cost == 1} to summon a Shadow Minion." if actions < action_cost

          updates[:current_actions] = actions - action_cost
        end
        trait_set.update!(updates)
        record_revision!(event_type: "shadow_minion_update", summary:, from_level: level, to_level: level)
      end
    end

    def record_initial_revision
      record_revision!(event_type: "created", summary: "Character created", from_level: level, to_level: level)
    end

    def playable_state_is_legal
      issues = creation_issues
      unless language_state_must_be_validated?
        language_source_refs = [
          Rules::NimbleCatalog.language_rules.fetch("source_ref"),
          *Rules::NimbleCatalog.language_rules.fetch("feature_language_choices", {}).values.map { |rule| rule.fetch("source_ref") }
        ]
        issues = issues.reject { |issue| language_source_refs.include?(issue.fetch(:source_ref)) }
      end

      issues.each do |issue|
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
      new_record? || character_class_id_changed? || ancestry_id_changed? || background_id_changed? || stat_array_changed? || stat_assignments_changed? || starting_equipment_choice_changed? || subclass_name_changed?
    end

    def should_sync_languages?
      new_record? || canonical_choices_changed? || language_choices_changed? || feature_language_choices_changed? || languages_changed? || level_changed?
    end

    def should_sync_starting_equipment?
      new_record? || character_class_id_changed? || starting_equipment_choice_changed? || (draft? && level_changed?)
    end

    def starting_gear_loadout_changed?
      saved_change_to_character_class_id? || saved_change_to_starting_equipment_choice?
    end

    def starting_gear_loadout_pending?
      will_save_change_to_character_class_id? || will_save_change_to_starting_equipment_choice?
    end

    def sync_starting_gear_inventory
      inventory_items.where(starting_gear: true).destroy_all
      return unless starting_equipment_choice == "class_gear" && character_class.present?

      Rules::NimbleCatalog.starting_gear_inventory_items(character_class.name).each do |item|
        armor_rules = Rules::NimbleCatalog.equipment_armor_item(item.fetch("name"))
        inventory_items.create!(
          name: item.fetch("name"),
          slots: item.fetch("slots"),
          starting_gear: true,
          source_ref: item.fetch("source_ref"),
          catalog_slots: item.fetch("slots"),
          equipped: armor_rules.present?
        )
      end
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

      assign_attributes_to_trait_set if trait_set.blank? || canonical_choices_changed? || subclass_name_changed?
    end

    def sync_languages
      self.language_choices = Array(language_choices).compact_blank.map(&:to_s)
      self.feature_language_choices = feature_language_choices.to_h.stringify_keys.transform_values { |items| Array(items).compact_blank.map(&:to_s) }

      return unless languages.blank? || (character_class.present? && stat_array.present?)

      self.languages = known_language_names.join(", ")
    end

    def sync_starting_equipment
      self.starting_equipment_choice = "class_gear" if starting_equipment_choice.blank?
      return if character_class.blank?

      previous_starting_equipment = starting_equipment
      previous_inventory = inventory
      choice_changed = new_record? || starting_equipment_choice_changed?
      if starting_equipment_choice == "starting_gold"
        should_grant_starting_gold = choice_changed || (draft? && level_changed?) || (draft? && current_gold.to_i.zero? && starting_equipment.blank?)
        self.current_gold = starting_gold_for_level if should_grant_starting_gold
        self.starting_equipment = "#{starting_gold_for_level} gp"
      else
        self.current_gold = 0 if choice_changed
        self.starting_equipment = starting_equipment_summary if choice_changed || character_class_id_changed? || starting_equipment.blank?
      end

      sync_legacy_inventory_note(previous_inventory, previous_starting_equipment) if new_record? || choice_changed || character_class_id_changed? || (draft? && level_changed?)
    end

    def sync_legacy_inventory_note(previous_inventory, previous_starting_equipment)
      return unless previous_inventory.blank? || previous_inventory == previous_starting_equipment

      self.inventory = starting_equipment
    end

    def starting_equipment_choice_only_changes_while_draft
      return unless persisted? && starting_equipment_choice_changed? && !draft?

      errors.add(:starting_equipment_choice, "can only be changed while the character is a draft")
    end

    def level_changes_require_level_up_transition
      return unless persisted? && will_save_change_to_level?
      return if @applying_level_up_transition
      return if attribute_in_database("status") == "draft" && !imported_character?

      errors.add(:level, "can only change through a finalized level-up")
    end

    def imported_progression_issues
      return [] unless imported_character?

      expected_levels = (2..level.to_i).to_a
      transitions = level_ups.order(:to_level, :id).map do |level_up|
        [ level_up.from_level, level_up.to_level, level_up.status ]
      end
      return [] if transitions.length == expected_levels.length && transitions.each_with_index.all? do |(from_level, to_level, status), index|
        from_level == expected_levels[index] - 1 && to_level == expected_levels[index] && status == "finalized"
      end

      [ rule_issue(
        "The imported level-up history does not match the character's current level.",
        "Chapter 4, Character Lifecycle",
        "An imported character can be finalized only when its complete sequential level-up history is preserved."
      ) ]
    end

    def canonical_choices_changed?
      character_class_id_changed? || ancestry_id_changed? || background_id_changed? || stat_array_changed? || stat_assignments_changed? || starting_equipment_choice_changed?
    end

    def language_state_must_be_validated?
      new_record? ||
        (will_save_change_to_status? && playable?) ||
        character_class_id_changed? || ancestry_id_changed? || background_id_changed? || stat_array_changed? || stat_assignments_changed? || level_changed? ||
        language_choices_changed? || feature_language_choices_changed? || languages_changed? || language_granting_feature_selection_changed?
    end

    def language_granting_feature_selection_changed?
      return false unless feature_choices_changed?

      language_feature_names = Rules::NimbleCatalog.language_rules.fetch("feature_language_choices", {}).keys
      previous_features = selected_feature_names(attribute_in_database("feature_choices"))
      current_features = selected_feature_names(feature_choices)
      changed_features = (previous_features - current_features) | (current_features - previous_features)
      changed_features.any? { |feature_name| language_feature_names.include?(feature_name) }
    end

    def selected_feature_names(selections)
      selections = selections.is_a?(Hash) ? selections : {}
      selections.values.flat_map do |pool_selections|
        if pool_selections.is_a?(Hash)
          pool_selections.values.flatten
        else
          Array(pool_selections)
        end
      end.compact_blank.map(&:to_s).uniq
    end

    def story_based_subclass_requires_approved_change
      return if subclass_name.blank? || character_class&.story_based_subclass_rule(subclass_name).blank?
      return unless new_record? || will_save_change_to_subclass_name?

      approval = @approved_story_subclass_change
      approved = approval.present? &&
        approval.fetch(:from_subclass) == attribute_in_database("subclass_name") &&
        approval.fetch(:to_subclass) == subclass_name &&
        approval.fetch(:story_note).present? &&
        approval.fetch(:campaign_id).present? &&
        approval.fetch(:approved_by_account_id).present?
      return if approved

      errors.add(:subclass_name, "requires a GM-approved story change with a story note")
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
      starting_hp = if character_class&.starting_hp
        character_class.starting_hp + derived_modifier_for(:max_hp_modifier, level: level_value, subclass_name: subclass_for_effects)
      end
      max_actions = max_actions_for(level: level_value, subclass_name: subclass_for_effects)
      max_hit_dice = max_hit_dice_for(level: level_value, subclass_name: subclass_for_effects)
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
        current_actions: max_actions,
        max_actions: max_actions,
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
        target.current_hp = if preserved_tracker_state[:current_hp].nil? && preserved_tracker_state[:previous_max_hp].nil?
          target.max_hp
        else
          preserved_or_clamped_value(
            preserved_tracker_state[:current_hp], preserved_tracker_state[:previous_max_hp], target.max_hp
          )
        end
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
      return current if new_max.nil?
      return new_max if previous_max.present? && current >= previous_max

      [ current, new_max ].compact.min
    end

    def language_selection_issues(stat_values = current_stat_values, choices: language_choices, feature_choices: recorded_feature_choices, feature_selections: feature_language_choices, level: self.level)
      source = Rules::NimbleCatalog.language_rules
      issues = []
      selections = Array(choices).map(&:to_s)
      feature_selections = feature_selections.to_h.stringify_keys.transform_values { |items| Array(items).compact_blank.map(&:to_s) }
      selected_features = feature_choices.to_h.values.flatten.map(&:to_s)
      base_grants = [ source.fetch("default_language"), *language_origin_grants(stat_values), *Rules::NimbleCatalog.class_language_grants_for(character_class&.name, level) ]
      allowed_choices = language_choice_options_for(
        stat_values,
        excluding: [],
        level:,
        feature_choices:,
        feature_language_choices: feature_selections
      )
      invalid = selections - allowed_choices

      if invalid.any?
        issues << rule_issue(
          "#{invalid.join(', ')} is not an available language choice for this character.",
          source.fetch("source_ref"),
          source.fetch("selection_note")
        )
      end

      if selections.uniq.length != selections.length
        issues << rule_issue("Choose each language only once.", source.fetch("source_ref"), source.fetch("source_quote"))
      end

      expected = language_choice_count(stat_values)
      if selections.length != expected
        difference = (selections.length - expected).abs
        message = if selections.length < expected
          "Choose #{difference} more language#{difference == 1 ? '' : 's'} for your INT."
        else
          "Remove #{difference} language choice#{difference == 1 ? '' : 's'}; your INT grants #{expected}."
        end
        issues << rule_issue(message, source.fetch("source_ref"), source.fetch("source_quote"))
      end

      language_features = source.fetch("feature_language_choices", {})
      feature_selections.each do |feature_name, picked_languages|
        next if language_features.key?(feature_name) && selected_features.include?(feature_name)
        next if picked_languages.empty?

        issues << rule_issue(
          "#{feature_name} does not grant language choices for this character.",
          source.fetch("source_ref"),
          source.fetch("selection_note")
        )
      end

      language_features.each do |feature_name, rule|
        next unless selected_features.include?(feature_name)

        picked_languages = feature_selections.fetch(feature_name, [])
        allowed_feature_languages = Array(rule.fetch("options")) - base_grants - selections
        invalid_languages = picked_languages - allowed_feature_languages
        if invalid_languages.any?
          issues << rule_issue(
            "#{invalid_languages.join(', ')} is not available for #{feature_name}.",
            rule.fetch("source_ref"),
            rule.fetch("source_quote")
          )
        end
        if picked_languages.uniq.length != picked_languages.length
          issues << rule_issue("Choose each language only once for #{feature_name}.", rule.fetch("source_ref"), rule.fetch("source_quote"))
        end
        expected_count = rule.fetch("count").to_i
        if picked_languages.length != expected_count
          difference = (picked_languages.length - expected_count).abs
          message = picked_languages.length < expected_count ? "Choose #{difference} more language#{difference == 1 ? '' : 's'} for #{feature_name}." : "Remove #{difference} extra language choice#{difference == 1 ? '' : 's'} for #{feature_name}."
          issues << rule_issue(message, rule.fetch("source_ref"), rule.fetch("source_quote"))
        end
      end

      additions = selections + feature_selections.values.flatten
      if additions.uniq.length != additions.length
        issues << rule_issue("A language cannot be selected more than once, including language grants from features.", source.fetch("source_ref"), source.fetch("source_quote"))
      end
      issues
    end

    def known_feature_languages(feature_selections, picked_languages)
      selected_features = feature_selections.to_h.values.flatten.map(&:to_s)
      picks = picked_languages.to_h.stringify_keys
      Rules::NimbleCatalog.language_rules.fetch("feature_language_choices", {}).filter_map do |feature_name, rule|
        next unless selected_features.include?(feature_name)

        Array(picks[feature_name]).map(&:to_s) & Array(rule.fetch("options"))
      end.flatten.uniq
    end

  private
    def initiative_trigger_summaries
      story_subclass_initiative_trigger_entries.map do |trigger|
        case trigger.fetch("kind")
        when "free_movement"
          "#{trigger.fetch('feature_name')} triggered its free movement on Initiative; move up to half your speed ignoring difficult terrain (resolve at the table; #{trigger.fetch('source_ref')})"
        else
          raise ArgumentError, "#{trigger.fetch('feature_name')} Initiative trigger is not supported yet. #{trigger.fetch('source_ref')}."
        end
      end
    end

    def initiative_feature_action_summaries(feature_actions)
      unless feature_actions.respond_to?(:each_pair)
        raise ArgumentError, "Initiative feature actions must be submitted as a structured selection."
      end

      submitted_actions = feature_actions.to_h.stringify_keys
      available_actions = initiative_optional_action_entries.index_by { |action| action.fetch("key") }
      unsupported_actions = submitted_actions.keys - available_actions.keys
      if unsupported_actions.any?
        raise ArgumentError, "This character does not have that Initiative feature action."
      end

      available_actions.filter_map do |key, action|
        submitted = submitted_actions[key]
        next if submitted.blank?
        unless submitted.respond_to?(:each_pair)
          raise ArgumentError, "Initiative feature action details must be submitted as a structured selection."
        end

        attributes = submitted.to_h.stringify_keys
        if (attributes.keys - %w[used target choice]).any?
          raise ArgumentError, "Initiative feature action contains unsupported details."
        end
        next unless [ "1", "true", true ].include?(attributes["used"])

        case action.fetch("kind")
        when "free_spell_cast"
          target = initiative_feature_action_target(attributes, action)

          spell = Spell.find_by(name: action.fetch("spell_name"))
          raise ArgumentError, "#{action.fetch('feature_name')} spell data is unavailable. #{action.fetch('source_ref')}." unless spell

          "#{action.fetch('feature_name')} cast #{spell.name} at Tier #{spell.tier} for free on #{target} (#{action.fetch('source_ref')}; resolve spell effects and any upcast at the table)"
        when "free_feature_use"
          target = initiative_feature_action_target(attributes, action)
          "#{action.fetch('feature_name')} used #{action.fetch('action_name')} for free on #{target} (#{action.fetch('source_ref')}; apply the feature effect at the table)"
        when "free_choice"
          choice = attributes.fetch("choice", "").to_s
          unless action.fetch("choices").include?(choice)
            raise ArgumentError, "Choose a valid #{action.fetch('feature_name')} option. #{action.fetch('source_ref')}."
          end

          limitation = choice == "Beastshift" && action["beastshift_grants_temp_hp"] == false ? "; free Beastshifting grants no temporary HP" : ""
          "#{action.fetch('feature_name')} chose #{choice} for free on Initiative (#{action.fetch('source_ref')}#{limitation}; resolve form or movement effects at the table)"
        else
          raise ArgumentError, "#{action.fetch('feature_name')} Initiative action is not supported yet. #{action.fetch('source_ref')}."
        end
      end
    end

    def initiative_feature_action_target(attributes, action)
      target = attributes.fetch("target", "").to_s.strip
      maximum_length = action.fetch("target_max_length", 80).to_i
      return target if target.present? && target.length <= maximum_length

      raise ArgumentError, "Name the #{action.fetch('target_label').downcase} for #{action.fetch('feature_name')} (#{maximum_length} characters maximum)."
    end

    def current_stat_values
      {
        "strength" => stat_set&.strength.to_i,
        "dexterity" => stat_set&.dexterity.to_i,
        "intelligence" => stat_set&.intelligence.to_i,
        "will" => stat_set&.will.to_i
      }
    end

    def parse_initiative_die_result(result)
      return result if result.is_a?(Integer)
      return unless result.is_a?(String) && result.match?(/\A\d+\z/)

      result.to_i
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

      minimum_formula_match = formula.match(/\AMIN\(\s*(STR|DEX|INT|WIL)\s*,\s*LVL\s*\)\z/i)
      if minimum_formula_match
        stat = { "STR" => "strength", "DEX" => "dexterity", "INT" => "intelligence", "WIL" => "will" }.fetch(minimum_formula_match[1].upcase)
        return [ value_for_stat(stat_values, stat), level.to_i ].min
      end

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

    def resource_tracks_after_encounter_end
      baseline = derived_resource_tracks_for(stat_values: current_stat_values).index_by { |track| track.fetch("key") }

      Array(trait_set&.resource_tracks).map do |track|
        track = track.to_h.stringify_keys
        reset_events = Array(track["reset_events"].presence || baseline.dig(track.fetch("key"), "reset_events"))
        next track unless reset_events.include?("encounter_end")

        initial_current = track["initial_current"] || baseline.dig(track.fetch("key"), "initial_current")
        next track if initial_current.nil?

        track.merge("current" => initial_current.to_i, "reset_events" => reset_events)
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
      background_spell_choices = Rules::NimbleCatalog.background_spell_choices
      background_spell_choices.each do |choice_background, definition|
        next if choice_background == background&.name

        selections = spell_choice_selections_for(choice_background, 1)
        next if selections.empty?

        label = definition.fetch("choice_label", "spell")
        issues << rule_issue(
          "#{choice_background}'s #{label} choice is not available unless that background is selected.",
          definition.fetch("source_ref"),
          definition.fetch("source_quote")
        )
      end

      pool = starting_background_spell_choice_pool
      return if pool.blank?

      pool_name = pool.fetch("name")
      label = pool.fetch("choice_label", "spell")
      selections = spell_choice_selections_for(pool_name, 1)
      count = pool.fetch("count").to_i

      if selections.length != count
        choice_count = "#{count} #{label} choice#{'s' unless count == 1}"
        issues << rule_issue(
          "#{pool_name} requires #{choice_count}.",
          pool.fetch("source_ref"),
          pool.fetch("source_quote")
        )
      end

      if pool.fetch("distinct", false) && selections.uniq.length != selections.length
        issues << rule_issue(
          "#{pool_name} choices must be different.",
          pool.fetch("source_ref"),
          pool.fetch("source_quote")
        )
      end

      invalid_selections = selections - Array(pool.fetch("options"))
      invalid_selections.each do |selection|
        issues << rule_issue(
          "#{selection} is not a #{label} option for #{pool_name}.",
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
      starting_hp = if character_class&.starting_hp
        character_class.starting_hp + derived_modifier_for(:max_hp_modifier, level: level_value, subclass_name: subclass_for_effects)
      end
      max_actions = max_actions_for(level: level_value, subclass_name: subclass_for_effects)
      stat_values = current_stat_values
      initiative = initiative_for(stat_values, level: level_value, subclass_name: subclass_for_effects)
      speed = speed_for(level: level_value, subclass_name: subclass_for_effects)
      max_hit_dice = max_hit_dice_for(level: level_value, subclass_name: subclass_for_effects)
      armor = armor_for(stat_values, level: level_value, subclass_name: subclass_for_effects).to_i + derived_modifier_for(:armor_modifier, level: level_value, subclass_name: subclass_for_effects)
      max_wounds = DEFAULT_MAX_WOUNDS + derived_modifier_for(:max_wounds_modifier, level: level_value, subclass_name: subclass_for_effects)
      resource_values = derived_resource_values_for(stat_values: stat_values, level: level_value, subclass_name: subclass_for_effects)

      build_trait_set initiative:        initiative,
                      speed:             speed,
                      hit_die:           hit_die,
                      current_hit_dice:  max_hit_dice,
                      max_hit_dice:      max_hit_dice,
                      current_actions:   max_actions,
                      max_actions:       max_actions,
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
