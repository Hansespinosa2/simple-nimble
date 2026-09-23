class Character < ApplicationRecord
  BASE_SPEED = 6
  DEFAULT_MAX_WOUNDS = 6
  BASE_INVENTORY_SLOTS = 10

  # Nimble creation-time stat arrays (02-rules-canon.md S-1 #1). The two
  # highest values go to the class's 2 Key Stats, the remaining two to the
  # 2 Secondary Stats.
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

  def available_spells
    spells = Spell.order(:tier, :name)
    return Spell.none if character_class.blank?

    spells.select { |spell| spell.available_to?(self) }
  end

  def starting_equipment_summary
    character_class&.starting_gear&.join(", ")
  end

  def save_dc_for(stat_values = nil)
    return nil if character_class.blank?

    values = stat_values || current_stat_values
    10 + character_class.key_stats.map { |stat| value_for_stat(values, stat) }.max.to_i
  end

  def mana_max_for(stat_values: nil, level: self.level)
    return nil if character_class.blank?

    formula = character_class.resource_rules.to_h.fetch("max_formula", "").to_s.split(";").first.to_s
    match = formula.match(/(?:mana\s+)?(STR|DEX|INT|WIL)\s*(?:\*\s*(\d+))?\s*\+\s*LVL/i)
    return nil unless match

    stat = { "STR" => "strength", "DEX" => "dexterity", "INT" => "intelligence", "WIL" => "will" }.fetch(match[1].upcase)
    multiplier = match[2].to_i.nonzero? || 1
    (value_for_stat(stat_values || current_stat_values, stat) * multiplier) + level.to_i
  end

  def derived_resource_values_for(stat_values:, level: self.level)
    rules = character_class&.resource_rules.to_h
    formula = rules["max_formula"].presence || rules["formula"].presence
    mana_max = mana_max_for(stat_values: stat_values, level: level)
    resource_max = mana_max.present? ? nil : resource_max_from_formula(formula, stat_values)

    {
      name: rules["name"],
      formula: formula,
      die: resource_die_for(rules["die_by_level"], level),
      max_mana: mana_max,
      max_resource: resource_max
    }
  end

  def creation_issues
    issues = []
    issues << rule_issue("Choose a class before finalizing.", "Chapter 2, Class Rules", "Every hero has one class.") if character_class.blank?
    issues << rule_issue("Choose an ancestry before finalizing.", "Chapter 2, Ancestry Rules", "Every hero has one ancestry.") if ancestry.blank?
    issues << rule_issue("Choose a background before finalizing.", "Chapter 2, Backgrounds", "Every hero has one background.") if background.blank?
    issues << rule_issue("Choose a stat array before finalizing.", "Chapter 3, Character Creation", "Choose Standard, Balanced, or Min-Max and assign it to your class stats.") if stat_array.blank?
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

    stat_set.public_send(SKILL_TO_STAT.fetch(skill)).to_i + (ancestry&.all_skills_bonus || 0)
  end

  def skill_value(skill)
    skill_set&.public_send(skill)
  end

  def stat_value(stat)
    stat_set&.public_send(stat).to_i
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
        "name", "race", "nimble_class", "level", "legacy_background_text", "description", "languages", "spell_school_choice", "starting_equipment",
        "status", "conditions", "inventory", "game_notes", "stat_array"
      ),
      "rules" => {
        "class" => character_class&.name,
        "ancestry" => ancestry&.name,
        "background" => background&.name,
        "ruleset" => rules_context_label
      },
      "stats" => stat_set&.attributes&.slice("strength", "dexterity", "intelligence", "will"),
      "skills" => skill_set&.attributes&.slice(*SKILL_NAMES),
      "traits" => trait_set&.attributes&.slice(
        "initiative", "speed", "hit_die", "current_hit_dice", "max_hit_dice", "current_actions", "max_actions",
        "armor", "save_dc", "max_mana", "current_mana", "resource_name", "resource_formula", "resource_die", "max_resource", "current_resource",
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
      new_record? || character_class_id_changed? || ancestry_id_changed? || stat_array_changed?
    end

    def sync_derived_values
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
      character_class_id_changed? || ancestry_id_changed? || stat_array_changed?
    end

    def assign_attributes_to_stat_set(values)
      target = stat_set || build_stat_set
      target.assign_attributes(values)
    end

    def assign_attributes_to_skill_set
      target = skill_set || build_skill_set
      SKILL_NAMES.each do |skill|
        baseline = stat_set.public_send(SKILL_TO_STAT.fetch(skill)).to_i + (ancestry&.all_skills_bonus || 0)
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
          temp_hp: target.temp_hp
        }
      end
      level_value = level.to_i.positive? ? level.to_i : 1
      dexterity = stat_set&.dexterity.to_i
      starting_hp = character_class&.starting_hp || 10
      max_hit_dice = level_value + ancestry_modifier(:max_hit_dice_modifier)
      max_wounds = DEFAULT_MAX_WOUNDS + ancestry_modifier(:max_wounds_modifier)
      stat_values = current_stat_values
      resource_values = derived_resource_values_for(stat_values: stat_values, level: level_value)
      target.assign_attributes(
        initiative: dexterity + ancestry_modifier(:initiative_modifier),
        speed: BASE_SPEED + ancestry_modifier(:speed_modifier),
        hit_die: character_class&.hit_die || "1d6",
        current_hit_dice: max_hit_dice,
        max_hit_dice: max_hit_dice,
        current_actions: 3,
        max_actions: 3,
        armor: dexterity + ancestry_modifier(:armor_modifier),
        save_dc: save_dc_for(stat_values),
        max_mana: resource_values.fetch(:max_mana),
        current_mana: resource_values.fetch(:max_mana),
        resource_name: resource_values.fetch(:name),
        resource_formula: resource_values.fetch(:formula),
        resource_die: resource_values.fetch(:die),
        max_resource: resource_values.fetch(:max_resource),
        current_resource: resource_values.fetch(:max_resource),
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
      languages << "Dwarvish" if %w[Dwarf Gnome Half-Giant].include?(ancestry&.name) && stat_value("intelligence") >= 0
      languages << "Elvish" if %w[Elf Dryad/Shroomling].include?(ancestry&.name) && stat_value("intelligence") >= 0
      languages << "Goblin" if %w[Goblin Orc].include?(ancestry&.name) && stat_value("intelligence") >= 0
      languages << "Draconic" if %w[Dragonborn Kobold].include?(ancestry&.name) && stat_value("intelligence") >= 0
      languages << "Celestial" if ancestry&.name == "Celestial" && stat_value("intelligence") >= 0
      (stat_value("intelligence").positive? ? stat_value("intelligence") : 0).times do |index|
        languages << [ "Dwarvish", "Elvish", "Goblin", "Infernal", "Thieves' Cant", "Celestial", "Draconic", "Primordial", "Deep Speak" ][index] || "Additional language"
      end
      languages.uniq.join(", ")
    end

  private
    def ancestry_modifier(attribute)
      ancestry&.public_send(attribute) || 0
    end

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

    def build_projected_stat_set
      return nil unless character_class.present? && stat_array.present?

      StatSet.new(projected_stat_values)
    end

    def projected_stat_values
      values = Array(STAT_ARRAYS[stat_array]).sort.reverse
      keys = character_class.key_stats
      secondaries = character_class.secondary_stats

      { keys[0] => values[0], keys[1] => values[1],
        secondaries[0] => values[2], secondaries[1] => values[3] }.symbolize_keys
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
      all_skills_bonus = ancestry_modifier(:all_skills_bonus)

      build_skill_set arcana: all_skills_bonus,
                      insight: all_skills_bonus,
                      examination: all_skills_bonus,
                      finesse: all_skills_bonus,
                      might: all_skills_bonus,
                      lore: all_skills_bonus,
                      influence: all_skills_bonus,
                      naturecraft: all_skills_bonus,
                      stealth: all_skills_bonus,
                      perception: all_skills_bonus
    end

    def build_default_trait_set
      hit_die = character_class&.hit_die || "1d6"
      starting_hp = character_class&.starting_hp || 10
      initiative = ancestry_modifier(:initiative_modifier)
      speed = BASE_SPEED + ancestry_modifier(:speed_modifier)
      max_hit_dice = 1 + ancestry_modifier(:max_hit_dice_modifier)
      armor = ancestry_modifier(:armor_modifier)
      max_wounds = DEFAULT_MAX_WOUNDS + ancestry_modifier(:max_wounds_modifier)
      stat_values = current_stat_values
      resource_values = derived_resource_values_for(stat_values: stat_values, level: 1)

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
                      current_mana:      resource_values.fetch(:max_mana),
                      resource_name:     resource_values.fetch(:name),
                      resource_formula:  resource_values.fetch(:formula),
                      resource_die:      resource_values.fetch(:die),
                      max_resource:      resource_values.fetch(:max_resource),
                      current_resource:  resource_values.fetch(:max_resource),
                      inventory_slots:   BASE_INVENTORY_SLOTS + stat_values.fetch("strength"),
                      temp_hp:           0,
                      current_hp:        starting_hp,
                      max_hp:            starting_hp,
                      current_wounds:    0,
                      max_wounds:        max_wounds
    end
end
