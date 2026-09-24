class LevelUpPlanner
  attr_reader :character, :level_up

  def initialize(character, level_up)
    @character = character
    @level_up = level_up
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
    Character::SKILL_NAMES.select { |skill| character.skill_value(skill).to_i < max_skill_value }
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

  def story_based_subclass_rules
    character.character_class&.story_based_subclass_rules || []
  end

  def subclass_selection_required?
    target_level == 3 && character.subclass_name.blank? && subclass_options.present?
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
    character.feature_choice_pools_for(target_level).map do |pool|
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
      stats[stat_name] += 1 if stat_options.include?(stat_name)
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
      result << issue("Choose a subclass for #{character.character_class.name}.", character.character_class.source_reference, "At level 3, choose a subclass for your class.")
    elsif level_up.subclass_name.present?
      story_rule = character.character_class&.story_based_subclass_rule(level_up.subclass_name)
      if story_rule
        result << issue(
          "#{level_up.subclass_name} is story-based and requires a GM-approved story change, not an ordinary level-up choice.",
          story_rule.fetch("source_ref"),
          story_rule.fetch("source_quote")
        )
      elsif target_level != 3 || character.subclass_name.present?
        result << issue("A subclass can only be chosen once at level 3.", character.character_class&.source_reference || "Heroes 2.0.1, Subclasses", "Subclass selection is a level-3 class feature.")
      elsif !subclass_options.include?(level_up.subclass_name)
        result << issue("#{level_up.subclass_name} is not a legal subclass for #{character.character_class.name}.", character.character_class.source_reference, "Choose one of the subclasses listed for the class.")
      end
    end

    validate_feature_choices(result)
    validate_spell_choices(result)

    if level_up.skill_name.blank?
      result << issue("Choose one skill to improve.", "Chapter 3, Skills", "Each level grants 1 skill point.")
    elsif !Character::SKILL_NAMES.include?(level_up.skill_name)
      result << issue("#{level_up.skill_name.to_s.humanize} is not a recognized skill.", "Chapter 3, Skills", "Choose one of the ten skills listed in the character rules.")
    elsif !skill_options.include?(level_up.skill_name)
      result << issue("#{level_up.skill_name.to_s.humanize} is already at the +#{max_skill_value} skill maximum.", max_skill_source_ref, max_skill_source_quote)
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
      if stat_increase_type == "any_two"
        if selected_stats.length != 2 || selected_stats.uniq.length != 2
          result << issue("Choose two different stats to increase.", stat_increase_source_ref, stat_increase_quote)
        end
      elsif level_up.second_stat_name.present?
        result << issue("Only one stat can increase at this level.", stat_increase_source_ref, stat_increase_quote)
      elsif level_up.stat_name.blank?
        result << issue("Choose a #{stat_increase_type} stat to increase.", stat_increase_source_ref, stat_increase_quote)
      end

      selected_stats.each do |stat_name|
        if !stat_options.include?(stat_name)
          result << issue("#{stat_name.to_s.humanize} is not eligible for this level's stat increase.", stat_increase_source_ref, stat_increase_quote)
        elsif character.stat_value(stat_name) >= max_stat_value
          result << issue("#{stat_name.to_s.humanize} is already at the +#{max_stat_value} stat maximum.", max_stat_source_ref, max_stat_source_quote)
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
      result << issue("#{level_up.skill_from.to_s.humanize} cannot become negative when moving a skill point.", "Chapter 3, Skills", "You may move 1 point only as long as the source skill does not become negative.")
    end
    if level_up.skill_name.present? && Character::SKILL_NAMES.include?(level_up.skill_name) && projected_skills.fetch(level_up.skill_name) > max_skill_value
      result << issue("#{level_up.skill_name.to_s.humanize} would exceed the +#{max_skill_value} skill maximum.", max_skill_source_ref, max_skill_source_quote)
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
    skills = Character::SKILL_NAMES.index_with { |skill| character.skill_value(skill).to_i }
    traits = {
      "max_hp" => character.trait_set&.max_hp.to_i,
      "hit_die" => character.trait_set&.hit_die.presence || character.character_class&.hit_die || "1d6",
      "current_hp" => character.trait_set&.current_hp.to_i,
      "current_wounds" => character.trait_set&.current_wounds.to_i,
      "max_wounds" => character.trait_set&.max_wounds.to_i,
      "max_hit_dice" => character.trait_set&.max_hit_dice.to_i,
      "current_hit_dice" => character.trait_set&.current_hit_dice.to_i,
      "initiative" => character.trait_set&.initiative.to_i,
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

    selected_stats = [ level_up.stat_name, level_up.second_stat_name ].compact_blank
    selected_stats.each do |stat_name|
      next unless stat_options.include?(stat_name)

      Character::SKILL_NAMES.each do |skill|
        skills[skill] += 1 if Character::SKILL_TO_STAT.fetch(skill) == stat_name
      end
    end

    skills[level_up.skill_name] += 1 if level_up.skill_name.present? && skills.key?(level_up.skill_name)
    if level_up.skill_from.present? && skills.key?(level_up.skill_from) && level_up.skill_from != level_up.skill_name
      skills[level_up.skill_from] -= 1
      skills[level_up.skill_name] += 1 if skills.key?(level_up.skill_name)
    end

    hp_gain = [ level_up.hit_die_roll_one.to_i, level_up.hit_die_roll_two.to_i ].max
    if character.trait_set
      traits["max_hp"] += hp_gain
      current_level = character.level.to_i.positive? ? character.level.to_i : 1
      current_max_hp_modifier = character.derived_modifier_for(:max_hp_modifier, level: current_level, subclass_name: character.subclass_name)
      target_max_hp_modifier = character.derived_modifier_for(:max_hp_modifier, level: target_level, subclass_name: selected_subclass_name)
      traits["max_hp"] += target_max_hp_modifier - current_max_hp_modifier
      traits["current_hp"] = traits["max_hp"] if character.trait_set.current_hp.to_i >= character.trait_set.max_hp.to_i
      traits["max_hit_dice"] = target_level + character.derived_modifier_for(:max_hit_dice_modifier, level: target_level, subclass_name: selected_subclass_name)
      traits["current_hit_dice"] = [ character.trait_set.current_hit_dice.to_i + 1, traits["max_hit_dice"] ].min
      traits["initiative"] = character.initiative_for(stats, level: target_level, subclass_name: selected_subclass_name)
      traits["speed"] = character.speed_for(level: target_level, subclass_name: selected_subclass_name)
      traits["hit_die"] = character.hit_die_for(level: target_level, subclass_name: selected_subclass_name)
      traits["armor"] = character.armor_for(stats, level: target_level, subclass_name: selected_subclass_name).to_i + character.derived_modifier_for(:armor_modifier, level: target_level, subclass_name: selected_subclass_name)
      traits["max_wounds"] = Character::DEFAULT_MAX_WOUNDS + character.derived_modifier_for(:max_wounds_modifier, level: target_level, subclass_name: selected_subclass_name)
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

      level_up.roll_hit_die!(hit_die_size)
    end

    def projected_skill_values
      skills = Character::SKILL_NAMES.index_with { |skill| character.skill_value(skill).to_i }
      selected_stats = [ level_up.stat_name, level_up.second_stat_name ].compact_blank
      selected_stats.each do |stat_name|
        next unless stat_options.include?(stat_name)

        Character::SKILL_NAMES.each do |skill|
          skills[skill] += 1 if Character::SKILL_TO_STAT.fetch(skill) == stat_name
        end
      end
      skills[level_up.skill_name] += 1 if level_up.skill_name.present? && skills.key?(level_up.skill_name)
      if level_up.skill_from.present? && skills.key?(level_up.skill_from) && level_up.skill_from != level_up.skill_name
        skills[level_up.skill_from] -= 1
        skills[level_up.skill_name] += 1 if skills.key?(level_up.skill_name)
      end
      skills
    end

    def preserved_tracker_value(current, previous_max, new_max)
      return nil if current.nil?
      return new_max if previous_max.present? && current >= previous_max

      [ current, new_max ].compact.min
    end

    def validate_feature_choices(result)
      pools = character.feature_choice_pools_for(target_level)
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
            "Choose #{expected_count} option#{expected_count == 1 ? '' : 's'} from the #{pool_name} list."
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
          result << issue(
            "#{repeated_across_pools.join(', ')} has already been selected from another Commander ability list.",
            pool.fetch("source_ref"),
            "Choose another ability; the Commander may not select the same Combat Ability twice."
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
      end

      validate_arcane_command_choices(result)
    end

    def available_feature_options(pool, selected)
      if %w[arcane_command_order_or_spell arcane_command_combat_ability].include?(pool["story_choice_kind"] || pool["kind"])
        options = Array(pool.fetch("options", [])).select do |option|
          if option.start_with?("Order: ")
            order = option.delete_prefix("Order: ")
            recorded_order_selections.exclude?(order) && current_order_selections(pool.fetch("name")).exclude?(order)
          elsif option.start_with?("Spell: ")
            spell = option.delete_prefix("Spell: ")
            recorded_spell_selections.exclude?(spell) && current_spell_selections(pool.fetch("name")).exclude?(spell)
          else
            true
          end
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

    def validate_arcane_command_choices(result)
      return unless character.character_class&.name == "Commander" && character.subclass_name == "Spellblade"

      selected = feature_choices.values.flatten
      order_picks = recorded_order_selections + current_order_selections(nil)
      repeated_orders = order_picks.tally.select { |_order, count| count > 1 }.keys
      if repeated_orders.any?
        result << issue(
          "Choose a different Commander’s Order; #{repeated_orders.join(', ')} is already known.",
          "Heroes 2.0.1, p. 76",
          "Arcane Command lets the Spellblade choose another Commander’s Order or a tier 1 (or lower) spell."
        )
      end

      spell_picks = recorded_spell_selections + current_spell_selections(nil) + spell_choices.values.flatten
      known_spells = character.sheet_spells.pluck(:name) - character.story_granted_spell_names
      repeated_spells = (spell_picks & known_spells) | spell_picks.tally.select { |_spell, count| count > 1 }.keys
      return if repeated_spells.empty?

      result << issue(
        "Choose a different spell for each Arcane Command and Deep Knowledge choice; #{repeated_spells.join(', ')} is already selected.",
        "Heroes 2.0.1, p. 76",
        "Arcane Command grants one tier 1 (or lower) spell from any school in place of the class choice."
      )
    end

    def recorded_order_selections
      character.recorded_feature_choices.fetch("Commander's Orders", []) +
        character.recorded_feature_choices.values.flatten.filter_map do |selection|
          selection.delete_prefix("Order: ") if selection.start_with?("Order: ")
        end
    end

    def current_order_selections(except_pool_name)
      feature_choices.except(except_pool_name).values.flatten.filter_map do |selection|
        selection.delete_prefix("Order: ") if selection.start_with?("Order: ")
      end
    end

    def recorded_spell_selections
      subclass_spell_selections = character.recorded_spell_choices.values.flatten
      arcane_command_selections = character.recorded_feature_choices.values.flatten.filter_map do |selection|
        selection.delete_prefix("Spell: ") if selection.start_with?("Spell: ")
      end
      subclass_spell_selections + arcane_command_selections
    end

    def current_spell_selections(except_pool_name)
      feature_choices.except(except_pool_name).values.flatten.filter_map do |selection|
        selection.delete_prefix("Spell: ") if selection.start_with?("Spell: ")
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

      if stat_increase_type == "key"
        "At #{level_phrase}, increase one Key Stat by +1 (#{character.character_class.key_stats.map(&:upcase).to_sentence})."
      elsif stat_increase_type == "any_two"
        "At #{level_phrase}, increase any 2 different stats by +1."
      else
        "At #{level_phrase}, increase one Secondary Stat by +1 (#{character.character_class.secondary_stats.map(&:upcase).to_sentence})."
      end
    end

    def stat_increase_source_ref
      character.character_class&.source_reference || "Heroes 2.0.1, Class Progression"
    end

    def applied_explanations(stats, hp_gain)
      explanations = [
        {
          type: "applied",
          message: "Level #{target_level} grants 1 point to #{level_up.skill_name.to_s.humanize}.",
          source_ref: "Chapter 3, Skills",
          quote: "Each level grants +1 skill point."
        },
        {
          type: "auto_applied",
          message: "Max HP increases by #{hp_gain} (higher of #{level_up.hit_die_roll_one} and #{level_up.hit_die_roll_two} on #{character.hit_die_for(level: target_level, subclass_name: selected_subclass_name)}).",
          source_ref: "Chapter 3, Derived Values",
          quote: "HP Increase. Roll your Hit Die with advantage and increase your max HP by that much."
        }
      ]
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
          message: "1 point moves from #{level_up.skill_from.humanize} to #{level_up.skill_name.to_s.humanize}.",
          source_ref: "Chapter 3, Skills",
          quote: "You may move 1 point from one skill to another as long as the skill does not become negative."
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

    def issue(message, source_ref, quote)
      { message: message, source_ref: source_ref, quote: quote }
    end
end
