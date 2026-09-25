class LevelUpPlanner
  attr_reader :character, :level_up

  def initialize(character, level_up, random_number: SecureRandom.method(:random_number))
    @character = character
    @level_up = level_up
    @random_number = random_number
    ensure_hit_die_rolls
  end

  def target_level
    level_up.to_level.presence || character.level.to_i + 1
  end

  def stat_increase_type
    character.stat_increase_type_for(target_level)
  end

  def stat_options
    character.stat_increase_options_for(target_level)
  end

  def skill_options
    projected = projected_skill_values(include_skill_grant: false, include_skill_transfer: false)
    Character::SKILL_NAMES.select do |skill|
      increase = skill_points_per_level
      if level_up.skill_from.present? && Character::SKILL_NAMES.include?(level_up.skill_from) && level_up.skill_from != skill
        increase += skill_point_transfers_per_level
      end
      projected.fetch(skill) + increase <= max_skill_value
    end
  end

  def skill_points_per_level
    Rules::NimbleCatalog.derived_values.fetch("skill_points_per_level").to_i
  end

  def skill_point_transfers_per_level
    Rules::NimbleCatalog.derived_values.fetch("skill_point_transfers_per_level", 1).to_i
  end

  def skill_points_per_level_description
    count = skill_points_per_level
    "#{count} skill #{count == 1 ? 'point' : 'points'}"
  end

  def skill_point_transfers_per_level_description
    count = skill_point_transfers_per_level
    "#{count} #{count == 1 ? 'point' : 'points'}"
  end

  def skill_point_progression_source_ref
    Rules::NimbleCatalog.derived_values.fetch("skill_point_progression_source_ref")
  end

  def skill_point_progression_source_quote
    Rules::NimbleCatalog.derived_values.fetch("skill_point_progression_source_quote")
  end

  def skill_point_progression_note
    Rules::NimbleCatalog.derived_values.fetch("skill_point_progression_note")
  end

  def stat_increase_mechanic
    Rules::NimbleCatalog.stat_increase_mechanic_for(stat_increase_type)
  end

  def stat_increase_choice_count
    stat_increase_mechanic.fetch("choice_count", 0).to_i
  end

  def stat_increase_amount
    stat_increase_mechanic.fetch("amount", 0).to_i
  end

  def stat_increase_distinct?
    stat_increase_mechanic.fetch("distinct", false)
  end

  def stat_increase_label
    stat_increase_mechanic.fetch("label", stat_increase_type.to_s.humanize)
  end

  def stat_increase_choice_description
    if stat_increase_type == "any_two" && stat_increase_distinct? && stat_increase_choice_count > 1
      "Choose #{stat_increase_choice_count} different stats; each increases by +#{stat_increase_amount}."
    elsif stat_increase_distinct? && stat_increase_choice_count > 1
      "Choose #{stat_increase_choice_count} different #{stat_increase_label.pluralize} (#{stat_increase_option_text}); each increases by +#{stat_increase_amount}."
    else
      "Choose one #{stat_increase_label} to increase by +#{stat_increase_amount}."
    end
  end

  def max_stat_value
    Rules::NimbleCatalog.derived_values.fetch("max_stat").to_i
  end

  def max_skill_value
    Rules::NimbleCatalog.derived_values.fetch("max_skill").to_i
  end

  def max_level_value
    Character::MAX_LEVEL
  end

  def subclass_options
    character.subclass_options
  end

  def subclass_choice_level
    character.character_class&.subclass_choice_level
  end

  def story_based_subclass_rules
    character.character_class&.story_based_subclass_rules || []
  end

  def subclass_selection_required?
    subclass_choice_level.present? && target_level == subclass_choice_level && character.subclass_name.blank? && subclass_options.present?
  end

  def selected_subclass_name
    level_up.subclass_name.presence || character.subclass_name
  end

  def progression_preview
    klass = character.character_class
    subclass_name = level_up.subclass_name.presence || character.subclass_name

    {
      "features" => character.progression_features_for(target_level, subclass_name:),
      "subclass_features" => subclass_name.present? ? klass&.subclass_features_for(subclass_name, target_level).to_a : [],
      "feature_choices" => feature_choice_pools,
      "spell_choices" => spell_choice_pools,
      "subclass_name" => subclass_name,
      "source_ref" => klass&.source_reference
    }
  end

  def feature_choices
    raw_choices = level_up.feature_choices.respond_to?(:to_h) ? level_up.feature_choices.to_h : {}
    raw_choices.stringify_keys.transform_values do |selections|
      Array(selections).compact_blank.map(&:to_s)
    end
  end

  def feature_choice_pools
    return [] if character.character_class.blank?

    feature_choices_by_name = feature_choices
    character.feature_choice_pools_for(target_level, selected_feature_choices: feature_choices).map do |pool|
      pool_name = pool.fetch("name")
      selected = feature_choices_by_name.fetch(pool_name, [])
      pool.merge("options" => available_feature_options(pool, selected), "selected" => selected)
    end
  end

  def spell_choices
    raw_choices = level_up.spell_choices.respond_to?(:to_h) ? level_up.spell_choices.to_h : {}
    raw_choices.stringify_keys.transform_values do |selections|
      Array(selections).compact_blank.map(&:to_s)
    end
  end

  def spell_choice_pools
    spell_choices_by_name = spell_choices
    character.spell_choice_pools_for(target_level).map do |pool|
      pool.merge("selected" => spell_choices_by_name.fetch(pool.fetch("name"), []))
    end
  end

  def projected_stats
    stats = Character::STAT_NAMES.index_with { |stat| character.stat_value(stat) }
    [ level_up.stat_name, level_up.second_stat_name ].compact_blank.each do |stat_name|
      stats[stat_name] += stat_increase_amount if stat_options.include?(stat_name)
    end
    character.feature_choice_pools_for(target_level, selected_feature_choices: feature_choices).each do |pool|
      amount = pool.fetch("stat_increase_amount", 0).to_i
      next unless amount.positive?

      feature_choices.fetch(pool.fetch("name"), []).each do |stat_name|
        stats[stat_name] += amount if stats.key?(stat_name)
      end
    end
    stats
  end

  def language_choices_needed
    [ character.language_choice_count(projected_stats) - Array(character.language_choices).compact_blank.length, 0 ].max
  end

  def language_choice_options
    character.language_choice_options_for(
      projected_stats,
      excluding: character.language_choices,
      level: target_level,
      feature_choices: projected_feature_choices,
      feature_language_choices: projected_feature_language_choices
    )
  end

  def feature_language_choice_rules
    eligible_features = feature_choice_pools.flat_map { |pool| Array(pool.fetch("options")) + Array(pool.fetch("selected")) } + projected_feature_choices.values.flatten
    Rules::NimbleCatalog.language_rules.fetch("feature_language_choices", {}).select do |feature_name, _rule|
      eligible_features.include?(feature_name)
    end
  end

  def feature_language_choice_options(feature_name)
    rule = Rules::NimbleCatalog.language_feature_choice(feature_name)
    return [] unless rule

    selected = Array(level_up.feature_language_choices.to_h.stringify_keys[feature_name]).compact_blank.map(&:to_s)
    known = character.known_language_names(
      projected_stats,
      choices: projected_language_choices,
      level: target_level,
      feature_choices: projected_feature_choices,
      feature_language_choices: projected_feature_language_choices
    )
    (Array(rule.fetch("options")) - known + selected).uniq
  end

  def hit_die_size
    hit_die = character.hit_die_for(level: target_level, subclass_name: selected_subclass_name)
    hit_die.to_s.split("d").last.to_i.nonzero? || 6
  end

  def issues
    result = []
    result << issue("This character is not in a playable state.", "Chapter 4, Character Lifecycle", "Level-up begins from a PlayableValid character.") unless character.playable? || character.level_up_in_progress?
    result << issue("Resolve the character's creation checks before leveling up.", "Chapter 3, Character Creation", "A level-up can only begin from a legal character state.") unless character.creation_issues.empty?
    result << issue("This character is already at the maximum level.", max_level_source_ref, max_level_source_quote) if character.level.to_i >= max_level_value
    result << issue("This level-up has already been finalized.", "Chapter 4, Character Lifecycle", "A finalized transition cannot be applied twice.") if level_up.finalized?
    result << issue("Level-up must start from the character's current level.", "Chapter 4, Character Lifecycle", "A transition records the exact level it advances from.") unless level_up.from_level.to_i == character.level.to_i
    result << issue("Level-up must advance exactly one level.", "Chapter 3, Character Progression", "Level-up is an explicit one-level transition.") unless target_level == character.level.to_i + 1

    if subclass_selection_required? && level_up.subclass_name.blank?
      result << issue(
        "Choose a subclass for #{character.character_class.name} at level #{subclass_choice_level}.",
        character.character_class.source_reference,
        subclass_choice_source_quote
      )
    elsif level_up.subclass_name.present?
      story_rule = character.character_class&.story_based_subclass_rule(level_up.subclass_name)
      if story_rule
        result << issue(
          "#{level_up.subclass_name} is story-based and requires a GM-approved story change, not an ordinary level-up choice.",
          story_rule.fetch("source_ref"),
          story_rule.fetch("source_quote")
        )
      elsif subclass_choice_level.blank?
        result << issue("No subclass choice is defined for #{character.character_class.name}.", character.character_class.source_reference, "Subclass choice is missing from the published progression data.")
      elsif target_level != subclass_choice_level || character.subclass_name.present?
        result << issue(
          "A subclass can only be chosen once at level #{subclass_choice_level}.",
          character.character_class.source_reference,
          subclass_choice_source_quote
        )
      elsif !subclass_options.include?(level_up.subclass_name)
        result << issue("#{level_up.subclass_name} is not a legal subclass for #{character.character_class.name}.", character.character_class.source_reference, "Choose one of the subclasses listed for the class.")
      end
    end

    validate_feature_choices(result)
    validate_spell_choices(result)

    if level_up.skill_name.blank?
      result << issue(
        "Choose one skill to improve.",
        skill_point_progression_source_ref,
        skill_point_progression_source_quote,
        rule_note: skill_point_progression_note
      )
    elsif !Character::SKILL_NAMES.include?(level_up.skill_name)
      result << issue("#{level_up.skill_name.to_s.humanize} is not a recognized skill.", "Chapter 3, Skills", "Choose one of the ten skills listed in the character rules.")
    elsif !skill_options.include?(level_up.skill_name)
      message = if character.skill_value(level_up.skill_name).to_i >= max_skill_value
        "#{level_up.skill_name.to_s.humanize} is already at the +#{max_skill_value} skill maximum."
      else
        "#{level_up.skill_name.to_s.humanize} would exceed the +#{max_skill_value} skill maximum after this level's increases."
      end
      result << issue(message, max_skill_source_ref, max_skill_source_quote)
    end

    if level_up.skill_from.present?
      if !Character::SKILL_NAMES.include?(level_up.skill_from)
        result << issue("#{level_up.skill_from.to_s.humanize} is not a recognized skill to move.", "Chapter 3, Skills", "Choose one of the ten skills listed in the character rules.")
      elsif level_up.skill_from == level_up.skill_name
        result << issue("Choose a different skill to move from.", "Chapter 3, Skills", "The optional moved point must come from another skill.")
      end
    end

    if stat_increase_type.present?
      selected_stats = [ level_up.stat_name, level_up.second_stat_name ].compact_blank
      if selected_stats.length != stat_increase_choice_count || level_up.stat_name.blank? ||
          (stat_increase_choice_count > 1 && level_up.second_stat_name.blank?)
        result << issue(stat_increase_requirement_message, stat_increase_source_ref, stat_increase_quote)
      elsif stat_increase_distinct? && selected_stats.uniq.length != selected_stats.length
        result << issue(stat_increase_requirement_message, stat_increase_source_ref, stat_increase_quote)
      end

      selected_stats.each do |stat_name|
        if !stat_options.include?(stat_name)
          result << issue("#{stat_name.to_s.humanize} is not eligible for this level's stat increase.", stat_increase_source_ref, stat_increase_quote)
        elsif character.stat_value(stat_name) >= max_stat_value
          result << issue("#{stat_name.to_s.humanize} is already at the +#{max_stat_value} stat maximum.", max_stat_source_ref, max_stat_source_quote)
        elsif character.stat_value(stat_name) + stat_increase_amount > max_stat_value
          result << issue("#{stat_name.to_s.humanize} would exceed the +#{max_stat_value} stat maximum.", max_stat_source_ref, max_stat_source_quote)
        end
      end
    elsif level_up.stat_name.present? || level_up.second_stat_name.present?
      result << issue("No stat increase is scheduled at level #{target_level}.", character.character_class&.source_reference || "Heroes 2.0.1, Class Progression", "Stat increases occur at scheduled class progression levels.")
    end

    if level_up.hit_die_roll_one.blank? || level_up.hit_die_roll_two.blank?
      result << issue("Roll both Hit Dice before applying this level-up.", "Chapter 3, Derived Values", "Roll your Hit Die with advantage and increase max HP by the higher result.")
    elsif [ level_up.hit_die_roll_one, level_up.hit_die_roll_two ].any? { |roll| roll.to_i > hit_die_size }
      result << issue("Each Hit Die roll must be between 1 and #{hit_die_size}.", "Chapter 3, Derived Values", "Roll two results using the character's Hit Die.")
    end

    projected_skills = projected_skill_values
    if level_up.skill_from.present? && Character::SKILL_NAMES.include?(level_up.skill_from) && projected_skills.fetch(level_up.skill_from) < 0
      result << issue(
        "#{level_up.skill_from.to_s.humanize} cannot become negative when moving #{skill_point_transfers_per_level_description}.",
        "Chapter 3, Skills",
        "You may move #{skill_point_transfers_per_level_description} from one skill to another as long as the source skill does not become negative."
      )
    end

    character.language_issues_for(
      stat_values: projected_stats,
      choices: projected_language_choices,
      feature_choices: projected_feature_choices,
      feature_selections: projected_feature_language_choices,
      level: target_level
    ).each do |language_issue|
      result << issue(language_issue.fetch(:message), language_issue.fetch(:source_ref), language_issue.fetch(:quote))
    end

    result
  end

  def valid?
    issues.empty?
  end

  def explanations
    issues.map { |item| item.merge(type: "blocked", context: character.rules_context_label) }
  end

  def preview
    stats = projected_stats
    skills = projected_skill_values
    traits = {
      "max_hp" => character.trait_set&.max_hp.to_i,
      "hit_die" => character.trait_set&.hit_die.presence || character.character_class&.hit_die || "1d6",
      "current_hp" => character.trait_set&.current_hp.to_i,
      "current_wounds" => character.trait_set&.current_wounds.to_i,
      "max_wounds" => character.trait_set&.max_wounds.to_i,
      "max_hit_dice" => character.trait_set&.max_hit_dice.to_i,
      "current_hit_dice" => character.trait_set&.current_hit_dice.to_i,
      "initiative" => character.trait_set&.initiative.to_i,
      "max_actions" => character.trait_set&.max_actions.to_i,
      "speed" => character.trait_set&.speed.to_i,
      "armor" => character.trait_set&.armor.to_i,
      "inventory_slots" => character.trait_set&.inventory_slots.to_i,
      "save_dc" => character.trait_set&.save_dc,
      "max_mana" => character.trait_set&.max_mana,
      "current_mana" => character.trait_set&.current_mana,
      "resource_name" => character.trait_set&.resource_name,
      "resource_formula" => character.trait_set&.resource_formula,
      "resource_die" => character.trait_set&.resource_die,
      "max_resource" => character.trait_set&.max_resource,
      "current_resource" => character.trait_set&.current_resource,
      "resource_tracks" => character.trait_set&.resource_tracks
    }

    hp_gain = [ level_up.hit_die_roll_one.to_i, level_up.hit_die_roll_two.to_i ].max
    if character.trait_set
      traits["max_hp"] += hp_gain
      current_level = character.level.to_i.positive? ? character.level.to_i : 1
      current_max_hp_modifier = character.derived_modifier_for(:max_hp_modifier, level: current_level, subclass_name: character.subclass_name)
      target_max_hp_modifier = character.derived_modifier_for(:max_hp_modifier, level: target_level, subclass_name: selected_subclass_name, feature_choices: projected_feature_choices)
      traits["max_hp"] += target_max_hp_modifier - current_max_hp_modifier
      traits["current_hp"] = traits["max_hp"] if character.trait_set.current_hp.to_i >= character.trait_set.max_hp.to_i
      hit_dice_progression = Rules::NimbleCatalog.hit_dice_progression
      hit_dice_gain = hit_dice_progression.fetch("increase_per_level").to_i
      traits["max_hit_dice"] = character.max_hit_dice_for(level: target_level, subclass_name: selected_subclass_name, feature_choices: projected_feature_choices)
      traits["current_hit_dice"] = [ character.trait_set.current_hit_dice.to_i + hit_dice_gain, traits["max_hit_dice"] ].min
      traits["initiative"] = character.initiative_for(stats, level: target_level, subclass_name: selected_subclass_name, feature_choices: projected_feature_choices)
      traits["max_actions"] = character.max_actions_for(level: target_level, subclass_name: selected_subclass_name, feature_choices: projected_feature_choices)
      traits["speed"] = character.speed_for(level: target_level, subclass_name: selected_subclass_name, feature_choices: projected_feature_choices)
      traits["hit_die"] = character.hit_die_for(level: target_level, subclass_name: selected_subclass_name)
      traits["armor"] = character.armor_for(stats, level: target_level, subclass_name: selected_subclass_name, feature_choices: projected_feature_choices).to_i + character.derived_modifier_for(:armor_modifier, level: target_level, subclass_name: selected_subclass_name, feature_choices: projected_feature_choices)
      traits["max_wounds"] = Character::DEFAULT_MAX_WOUNDS + character.derived_modifier_for(:max_wounds_modifier, level: target_level, subclass_name: selected_subclass_name, feature_choices: projected_feature_choices)
      traits["current_wounds"] = preserved_tracker_value(character.trait_set.current_wounds, character.trait_set.max_wounds, traits["max_wounds"])
      traits["inventory_slots"] = Character::BASE_INVENTORY_SLOTS + stats.fetch("strength")
      resource_values = character.derived_resource_values_for(
        stat_values: stats,
        level: target_level,
        feature_choices: projected_feature_choices,
        subclass_name: selected_subclass_name
      )
      resource_tracks = character.preserved_resource_tracks(resource_values.fetch(:resource_tracks))
      legacy_resource_values = character.resource_tracker_values_for(resource_tracks)
      traits["resource_tracks"] = resource_tracks
      traits["save_dc"] = character.save_dc_for(stats)
      traits["max_mana"] = legacy_resource_values.fetch(:max_mana)
      traits["resource_name"] = resource_values.fetch(:name)
      traits["resource_formula"] = resource_values.fetch(:formula)
      traits["resource_die"] = resource_values.fetch(:die)
      traits["max_resource"] = legacy_resource_values.fetch(:max_resource)
      traits["current_mana"] = legacy_resource_values.fetch(:current_mana)
      traits["current_resource"] = legacy_resource_values.fetch(:current_resource)
    end

    {
      "level" => target_level,
      "stats" => stats,
      "skills" => skills,
      "traits" => traits,
      "hp_gain" => hp_gain,
      "hit_die_rolls" => [ level_up.hit_die_roll_one, level_up.hit_die_roll_two ],
      "stat_increase_type" => stat_increase_type,
      "subclass" => selected_subclass_name,
      "feature_choices" => feature_choices,
      "spell_choices" => spell_choices,
      "language_choices" => projected_language_choices,
      "feature_language_choices" => projected_feature_language_choices,
      "languages" => character.known_language_names(
        stats,
        choices: projected_language_choices,
        level: target_level,
        feature_choices: projected_feature_choices,
        feature_language_choices: projected_feature_language_choices
      ),
      "spell_tier" => spell_tier_for(target_level),
      "progression" => progression_preview,
      "explanations" => applied_explanations(stats, hp_gain)
    }
  end

  private
    def max_level_source_ref
      Rules::NimbleCatalog.derived_values.fetch("max_level_source_ref")
    end

    def max_level_source_quote
      Rules::NimbleCatalog.derived_values.fetch("max_level_source_quote")
    end

    def max_stat_source_ref
      Rules::NimbleCatalog.derived_values.fetch("max_stat_source_ref")
    end

    def max_stat_source_quote
      Rules::NimbleCatalog.derived_values.fetch("max_stat_source_quote")
    end

    def max_skill_source_ref
      Rules::NimbleCatalog.derived_values.fetch("max_skill_source_ref")
    end

    def max_skill_source_quote
      Rules::NimbleCatalog.derived_values.fetch("max_skill_source_quote")
    end

    def subclass_choice_source_quote
      character.character_class.features_for(subclass_choice_level).find { |feature| feature == "Subclass choice" }
    end

    def projected_language_choices
      (Array(character.language_choices).compact_blank.map(&:to_s) + Array(level_up.language_choices).compact_blank.map(&:to_s)).uniq
    end

    def projected_feature_language_choices
      existing = character.feature_language_choices.to_h.stringify_keys.transform_values { |items| Array(items).compact_blank.map(&:to_s) }
      submitted = level_up.feature_language_choices.to_h.stringify_keys.transform_values { |items| Array(items).compact_blank.map(&:to_s) }
      existing.merge(submitted)
    end

    def spell_tier_for(level)
      character.character_class&.spell_tier_for(level).to_i
    end

    def ensure_hit_die_rolls
      return if level_up.hit_die_roll_one.present? && level_up.hit_die_roll_two.present?

      level_up.roll_hit_die!(hit_die_size, random_number: @random_number)
    end

    def projected_skill_values(include_skill_grant: true, include_skill_transfer: true)
      skills = Character::SKILL_NAMES.index_with { |skill| character.skill_value(skill).to_i }
      selected_stats = [ level_up.stat_name, level_up.second_stat_name ].compact_blank
      stat_bonuses = Hash.new(0)
      selected_stats.each do |stat_name|
        next unless stat_options.include?(stat_name)

        stat_bonuses[stat_name] += stat_increase_amount
      end
      character.feature_choice_pools_for(target_level, selected_feature_choices: feature_choices).each do |pool|
        amount = pool.fetch("stat_increase_amount", 0).to_i
        next unless amount.positive?

        feature_choices.fetch(pool.fetch("name"), []).each do |stat_name|
          stat_bonuses[stat_name] += amount if Character::STAT_NAMES.include?(stat_name)
        end
      end
      Character::SKILL_NAMES.each do |skill|
        skills[skill] += stat_bonuses.fetch(Character::SKILL_TO_STAT.fetch(skill), 0)
      end
      if include_skill_grant && level_up.skill_name.present? && skills.key?(level_up.skill_name)
        skills[level_up.skill_name] += skill_points_per_level
      end
      if include_skill_transfer && level_up.skill_from.present? && skills.key?(level_up.skill_from) && level_up.skill_from != level_up.skill_name
        skills[level_up.skill_from] -= skill_point_transfers_per_level
        skills[level_up.skill_name] += skill_point_transfers_per_level if skills.key?(level_up.skill_name)
      end
      skills
    end

    def preserved_tracker_value(current, previous_max, new_max)
      return nil if current.nil?
      return new_max if previous_max.present? && current >= previous_max

      [ current, new_max ].compact.min
    end

    def validate_feature_choices(result)
      pools = character.feature_choice_pools_for(target_level, selected_feature_choices: feature_choices)
      known_pool_names = pools.map { |pool| pool.fetch("name") }

      feature_choices.each_key do |pool_name|
        next if known_pool_names.include?(pool_name)

        result << issue(
          "#{pool_name} is not a feature-choice pool unlocked at level #{target_level}.",
          character.character_class&.source_reference || "Heroes 2.0.1, Class Progression",
          "Only choices granted by the current level's class progression may be selected."
        )
      end

      pools.each do |pool|
        pool_name = pool.fetch("name")
        selections = feature_choices.fetch(pool_name, [])
        expected_count = pool.fetch("count").to_i
        option_names = Array(pool.fetch("options", []))

        if selections.length != expected_count
          plural = expected_count == 1 ? "option" : "options"
          result << issue(
            "Choose #{expected_count} #{pool_name} #{plural} at level #{target_level}.",
            pool.fetch("source_ref"),
            pool.fetch("source_quote", "Choose #{expected_count} option#{expected_count == 1 ? '' : 's'} from the #{pool_name} list.")
          )
        end

        invalid_options = selections - option_names
        unless invalid_options.empty?
          result << issue(
            "#{invalid_options.join(', ')} is not a legal #{pool_name} option.",
            pool.fetch("source_ref"),
            "Choose only options printed in the #{pool_name} list."
          )
        end

        repeatable_options = Array(pool.fetch("repeatable_options", []))
        unique_selections = pool.fetch("allow_repeat", false) ? [] : selections - repeatable_options
        if unique_selections.uniq.length != unique_selections.length
          result << issue(
            "Choose different #{pool_name} options.",
            pool.fetch("source_ref"),
            "A choice cannot be selected more than once unless the rules say repeats are allowed."
          )
        end

        prior_selections = character.recorded_feature_choices.fetch(pool_name, [])
        repeated_options = (selections - repeatable_options) & prior_selections
        unless repeated_options.empty?
          result << issue(
            "#{repeated_options.join(', ')} has already been chosen for #{pool_name}.",
            pool.fetch("source_ref"),
            "Choose a new option from the list at each scheduled choice."
          )
        end

        other_pool_names = Array(pool.fetch("unique_across_pools", [])) - [ pool_name ]
        prior_cross_pool_choices = other_pool_names.flat_map do |other_pool_name|
          character.recorded_feature_choices.fetch(other_pool_name, [])
        end
        current_cross_pool_choices = other_pool_names.flat_map do |other_pool_name|
          feature_choices.fetch(other_pool_name, [])
        end
        repeated_across_pools = (selections - repeatable_options) & (prior_cross_pool_choices + current_cross_pool_choices)
        unless repeated_across_pools.empty?
          pool_label = pool.fetch("unique_across_pools_label", "feature-choice pool")
          source_quote = pool.fetch("unique_across_pools_source_quote", pool.fetch("source_quote", "Choose a distinct option from the listed choices."))
          result << issue(
            "#{repeated_across_pools.join(', ')} has already been selected from another #{pool_label}.",
            pool.fetch("source_ref"),
            source_quote
          )
        end

        requirements = pool.fetch("requires", {})
        selections.each do |selection|
          required_options = Array(requirements.fetch(selection, []))
          available_options = character.recorded_feature_choices.fetch(pool_name, []) + selections
          next if (required_options - available_options).empty?

          result << issue(
            "#{selection} requires #{required_options.join(', ')} first.",
            pool.fetch("source_ref"),
            "Meet the prerequisite printed beside that option before selecting it."
          )
        end

        if pool.fetch("stat_increase_amount", 0).to_i.positive? && !pool.fetch("allow_exceeding_typical_stat_max", false)
          selections.select { |stat_name| option_names.include?(stat_name) }.each do |stat_name|
            next if character.stat_value(stat_name) < max_stat_value

            result << issue(
              "#{stat_name.humanize} is already at the +#{max_stat_value} stat maximum.",
              max_stat_source_ref,
              max_stat_source_quote
            )
          end
        end
      end

      validate_story_choice_groups(result)
    end

    def available_feature_options(pool, selected)
      story_choice_groups = Array(pool["story_choice_groups"])
      if story_choice_groups.present?
        group_rules = Rules::NimbleCatalog.story_subclass_choice_groups_for(character.character_class&.name, character.subclass_name).slice(*story_choice_groups)
        taken_by_group = group_rules.transform_values do |definition|
          Rules::StorySubclassChoiceGroups.selections_for(
            character:,
            definition:,
            feature_choices:,
            spell_choices:
          )
        end
        options = Array(pool.fetch("options", [])).reject do |option|
          matching_group = group_rules.find { |_name, rule| option.start_with?(rule.fetch("prefix")) }
          next false unless matching_group

          group_name, definition = matching_group
          taken_by_group.fetch(group_name).include?(option.delete_prefix(definition.fetch("prefix")))
        end
        return (options | selected)
      end

      pool_name = pool.fetch("name")
      repeatable_options = Array(pool.fetch("repeatable_options", []))
      prior_selections = character.recorded_feature_choices.fetch(pool_name, [])
      other_pool_names = Array(pool.fetch("unique_across_pools", [])) - [ pool_name ]
      prior_cross_pool_choices = other_pool_names.flat_map do |other_pool_name|
        character.recorded_feature_choices.fetch(other_pool_name, [])
      end
      current_cross_pool_choices = other_pool_names.flat_map do |other_pool_name|
        feature_choices.fetch(other_pool_name, [])
      end
      prior_choices = prior_selections + prior_cross_pool_choices + current_cross_pool_choices
      requirements = pool.fetch("requires", {})
      eligible_choices = character.recorded_feature_choices.fetch(pool_name, []) + selected

      Array(pool.fetch("options", [])).select do |option|
        can_repeat = repeatable_options.include?(option)
        not_previously_selected = pool.fetch("allow_repeat", false) || can_repeat || !prior_choices.include?(option)
        prerequisites_met = (Array(requirements.fetch(option, [])) - eligible_choices).empty?
        not_previously_selected && prerequisites_met
      end | selected
    end

    def validate_story_choice_groups(result)
      group_rules = Rules::NimbleCatalog.story_subclass_choice_groups_for(character.character_class&.name, character.subclass_name)
      Rules::StorySubclassChoiceGroups.conflicts_for(
        character:,
        definitions: group_rules,
        feature_choices:,
        spell_choices:
      ).each do |conflict|
        definition = group_rules.fetch(conflict.fetch(:group))
        message = definition.fetch("conflict_message").gsub("%{selections}", conflict.fetch(:selections).join(", "))
        result << issue(message, definition.fetch("source_ref"), definition.fetch("source_quote"))
      end
    end

    def projected_feature_choices
      character.recorded_feature_choices.each_with_object({}) do |(pool_name, selections), projected|
        projected[pool_name] = selections.dup
      end.tap do |projected|
        feature_choices.each do |pool_name, selections|
          projected[pool_name] = Array(projected[pool_name]) + selections
        end
      end
    end

    def validate_spell_choices(result)
      pools = character.spell_choice_pools_for(target_level)
      known_pool_names = pools.map { |pool| pool.fetch("name") }

      spell_choices.each_key do |pool_name|
        next if known_pool_names.include?(pool_name)

        result << issue(
          "#{pool_name} is not a spell-choice pool unlocked at level #{target_level}.",
          character.character_class&.source_reference || "Heroes 2.0.1, Utility Spells",
          "Only choices granted by the current level's spell progression may be selected."
        )
      end

      pools.each do |pool|
        pool_name = pool.fetch("name")
        selections = spell_choices.fetch(pool_name, [])
        expected_count = pool.fetch("count").to_i
        option_names = Array(pool.fetch("options", []))
        choice_quote = pool.fetch("source_quote", "Choose only a listed option from this level's spell-choice pool.")

        if selections.length != expected_count
          plural = expected_count == 1 ? "option" : "options"
          result << issue(
            "Choose #{expected_count} #{pool_name} #{plural} at level #{target_level}.",
            pool.fetch("source_ref"),
            choice_quote
          )
        end

        invalid_options = selections - option_names
        unless invalid_options.empty?
          result << issue(
            "#{invalid_options.join(', ')} is not a legal #{pool_name} choice.",
            pool.fetch("source_ref"),
            choice_quote
          )
        end

        prior_selections = character.recorded_spell_choices.fetch(pool_name, [])
        repeated_options = selections & prior_selections
        unless repeated_options.empty?
          result << issue(
            "#{repeated_options.join(', ')} has already been chosen for #{pool_name}.",
            pool.fetch("source_ref"),
            choice_quote
          )
        end
      end
    end

    def stat_increase_quote
      scheduled_levels = character.character_class&.stat_increase_levels_for(stat_increase_type).to_a
      level_phrase = scheduled_levels.one? ? "level #{scheduled_levels.first}" : "levels #{scheduled_levels.to_sentence}"

      if stat_increase_distinct? && stat_increase_choice_count > 1
        choices = if stat_increase_type == "any_two"
          "any #{stat_increase_choice_count} different stats"
        else
          "#{stat_increase_choice_count} different #{stat_increase_label.pluralize} (#{stat_increase_option_text})"
        end
        "At #{level_phrase}, increase #{choices} by +#{stat_increase_amount}."
      else
        "At #{level_phrase}, increase one #{stat_increase_label} by +#{stat_increase_amount} (#{stat_increase_option_text})."
      end
    end

    def stat_increase_option_text
      option_stats = case stat_increase_type
      when "key" then character.character_class.key_stats
      when "secondary" then character.character_class.secondary_stats
      else []
      end
      option_abbreviations = option_stats.map do |stat|
        Rules::NimbleCatalog.stats.fetch(stat).fetch("abbreviation")
      end
      option_abbreviations.to_sentence(two_words_connector: " or ", last_word_connector: " or ")
    end

    def stat_increase_requirement_message
      if stat_increase_distinct? && stat_increase_choice_count > 1
        count_word = stat_increase_choice_count == 2 ? "two" : stat_increase_choice_count.to_s
        target = stat_increase_type == "any_two" ? "different stats" : "different #{stat_increase_label.pluralize}"
        "Choose #{count_word} #{target} to increase."
      else
        "Choose a #{stat_increase_type} stat to increase."
      end
    end

    def stat_increase_source_ref
      character.character_class&.source_reference || "Heroes 2.0.1, Class Progression"
    end

    def applied_explanations(stats, hp_gain)
      hit_dice_progression = Rules::NimbleCatalog.hit_dice_progression
      hit_dice_increase = hit_dice_progression.fetch("increase_per_level").to_i
      max_hit_dice = character.max_hit_dice_for(level: target_level, subclass_name: selected_subclass_name)
      explanations = [
        {
          type: "applied",
          message: "Level #{target_level} grants #{skill_points_per_level_description} to #{level_up.skill_name.to_s.humanize}.",
          source_ref: skill_point_progression_source_ref,
          quote: skill_point_progression_source_quote,
          rule_note: skill_point_progression_note
        },
        {
          type: "auto_applied",
          message: "Max HP increases by #{hp_gain} (higher of #{level_up.hit_die_roll_one} and #{level_up.hit_die_roll_two} on #{character.hit_die_for(level: target_level, subclass_name: selected_subclass_name)}).",
          source_ref: "Chapter 3, Derived Values",
          quote: "HP Increase. Roll your Hit Die with advantage and increase your max HP by that much."
        },
        {
          type: "auto_applied",
          message: "Max Hit Dice increases by #{hit_dice_increase} to #{max_hit_dice}.",
          source_ref: hit_dice_progression.fetch("increase_source_ref"),
          quote: hit_dice_progression.fetch("increase_source_quote")
        }
      ]
      max_actions = character.max_actions_for(level: target_level, subclass_name: selected_subclass_name)
      if max_actions > character.trait_set.max_actions.to_i
        action_effects = character.derived_feature_effects(level: target_level, subclass_name: selected_subclass_name)
        explanations << {
          type: "auto_applied",
          message: "Maximum actions increase to #{max_actions}.",
          source_ref: action_effects.fetch("max_actions_modifier_source_ref", Rules::NimbleCatalog.derived_values.fetch("default_max_actions_source_ref")),
          quote: action_effects.fetch("max_actions_modifier_source_quote", Rules::NimbleCatalog.derived_values.fetch("default_max_actions_source_quote"))
        }
      end
      [ level_up.stat_name, level_up.second_stat_name ].compact_blank.each do |stat_name|
        explanations << {
          type: "applied",
          message: "#{stat_name.humanize} increases to #{stats.fetch(stat_name)}.",
          source_ref: stat_increase_source_ref,
          quote: stat_increase_quote
        }
      end
      if level_up.skill_from.present? && level_up.skill_from != level_up.skill_name
        explanations << {
          type: "applied",
          message: "#{skill_point_transfers_per_level_description.capitalize} #{skill_point_transfers_per_level == 1 ? 'moves' : 'move'} from #{level_up.skill_from.humanize} to #{level_up.skill_name.to_s.humanize}.",
          source_ref: "Chapter 3, Skills",
          quote: "You may move #{skill_point_transfers_per_level_description} from one skill to another as long as the source skill does not become negative."
        }
      end
      if preview_spell_tier = spell_tier_for(target_level)
        explanations << {
          type: "auto_applied",
          message: preview_spell_tier.positive? ? "This class can now access spells up to Tier #{preview_spell_tier}." : "This class has no canon spell-tier unlock at this level.",
          source_ref: "Chapter 3, Spell Tier Unlocks",
          quote: "Spell access is determined by class and current level."
        }
      end
      explanations
    end

    def issue(message, source_ref, quote, rule_note: nil)
      { message: message, source_ref: source_ref, quote: quote, rule_note: rule_note }.compact
    end
end
