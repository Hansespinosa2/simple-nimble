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
    Character::SKILL_NAMES.select { |skill| character.skill_value(skill).to_i < 12 }
  end

  def subclass_options
    character.subclass_options
  end

  def subclass_selection_required?
    target_level == 3 && character.subclass_name.blank? && subclass_options.present?
  end

  def hit_die_size
    hit_die = character.trait_set&.hit_die.presence || character.character_class&.hit_die
    hit_die.to_s.split("d").last.to_i.nonzero? || 6
  end

  def issues
    result = []
    result << issue("This character is not in a playable state.", "Chapter 4, Character Lifecycle", "Level-up begins from a PlayableValid character.") unless character.playable? || character.level_up_in_progress?
    result << issue("Resolve the character's creation checks before leveling up.", "Chapter 3, Character Creation", "A level-up can only begin from a legal character state.") unless character.creation_issues.empty?
    result << issue("This character is already at the maximum level.", "Chapter 3, Character Progression", "Characters advance from level 1 through level 20.") if character.level.to_i >= 20
    result << issue("This level-up has already been finalized.", "Chapter 4, Character Lifecycle", "A finalized transition cannot be applied twice.") if level_up.finalized?
    result << issue("Level-up must start from the character's current level.", "Chapter 4, Character Lifecycle", "A transition records the exact level it advances from.") unless level_up.from_level.to_i == character.level.to_i
    result << issue("Level-up must advance exactly one level.", "Chapter 3, Character Progression", "Level-up is an explicit one-level transition.") unless target_level == character.level.to_i + 1

    if subclass_selection_required? && level_up.subclass_name.blank?
      result << issue("Choose a subclass for #{character.character_class.name}.", character.character_class.source_reference, "At level 3, choose a subclass for your class.")
    elsif level_up.subclass_name.present?
      if target_level != 3 || character.subclass_name.present?
        result << issue("A subclass can only be chosen once at level 3.", character.character_class&.source_reference || "Heroes 2.0.1, Subclasses", "Subclass selection is a level-3 class feature.")
      elsif !subclass_options.include?(level_up.subclass_name)
        result << issue("#{level_up.subclass_name} is not a legal subclass for #{character.character_class.name}.", character.character_class.source_reference, "Choose one of the subclasses listed for the class.")
      end
    end

    if level_up.skill_name.blank?
      result << issue("Choose one skill to improve.", "Chapter 3, Skills", "Each level grants 1 skill point.")
    elsif !Character::SKILL_NAMES.include?(level_up.skill_name)
      result << issue("#{level_up.skill_name.to_s.humanize} is not a recognized skill.", "Chapter 3, Skills", "Choose one of the ten skills listed in the character rules.")
    elsif !skill_options.include?(level_up.skill_name)
      result << issue("#{level_up.skill_name.to_s.humanize} is already at the +12 skill maximum.", "Chapter 3, Skills", "Skill values cannot exceed +12.")
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
          result << issue("Choose two different stats to increase.", "Chapter 3, Stat Increases", stat_increase_quote)
        end
      elsif level_up.second_stat_name.present?
        result << issue("Only one stat can increase at this level.", "Chapter 3, Stat Increases", stat_increase_quote)
      elsif level_up.stat_name.blank?
        result << issue("Choose a #{stat_increase_type} stat to increase.", "Chapter 3, Stat Increases", stat_increase_quote)
      end

      selected_stats.each do |stat_name|
        if !stat_options.include?(stat_name)
          result << issue("#{stat_name.to_s.humanize} is not eligible for this level's stat increase.", "Chapter 3, Stat Increases", stat_increase_quote)
        elsif character.stat_value(stat_name) >= 5
          result << issue("#{stat_name.to_s.humanize} is already at the +5 stat maximum.", "Chapter 3, Stats", "Stats cannot exceed +5.")
        end
      end
    elsif level_up.stat_name.present? || level_up.second_stat_name.present?
      result << issue("No stat increase is scheduled at level #{target_level}.", "Chapter 3, Stat Increases", "Stat increases occur at scheduled class progression levels.")
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
    if level_up.skill_name.present? && Character::SKILL_NAMES.include?(level_up.skill_name) && projected_skills.fetch(level_up.skill_name) > 12
      result << issue("#{level_up.skill_name.to_s.humanize} would exceed the +12 skill maximum.", "Chapter 3, Skills", "Skill values cannot exceed +12.")
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
    stats = Character::STAT_NAMES.index_with { |stat| character.stat_value(stat) }
    skills = Character::SKILL_NAMES.index_with { |skill| character.skill_value(skill).to_i }
    traits = {
      "max_hp" => character.trait_set&.max_hp.to_i,
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
      "current_resource" => character.trait_set&.current_resource
    }

    selected_stats = [ level_up.stat_name, level_up.second_stat_name ].compact_blank
    selected_stats.each do |stat_name|
      next unless stat_options.include?(stat_name)

      stats[stat_name] += 1
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
      traits["current_hp"] = traits["max_hp"] if character.trait_set.current_hp.to_i >= character.trait_set.max_hp.to_i
      traits["max_hit_dice"] = target_level + character.derived_modifier_for(:max_hit_dice_modifier)
      traits["current_hit_dice"] = [ character.trait_set.current_hit_dice.to_i + 1, traits["max_hit_dice"] ].min
      traits["initiative"] = stats.fetch("dexterity") + character.derived_modifier_for(:initiative_modifier)
      traits["speed"] = Character::BASE_SPEED + character.derived_modifier_for(:speed_modifier)
      traits["armor"] = character.armor_for(stats).to_i + character.derived_modifier_for(:armor_modifier)
      traits["max_wounds"] = Character::DEFAULT_MAX_WOUNDS + character.derived_modifier_for(:max_wounds_modifier)
      traits["current_wounds"] = preserved_tracker_value(character.trait_set.current_wounds, character.trait_set.max_wounds, traits["max_wounds"])
      traits["inventory_slots"] = Character::BASE_INVENTORY_SLOTS + stats.fetch("strength")
      resource_values = character.derived_resource_values_for(stat_values: stats, level: target_level)
      traits["save_dc"] = character.save_dc_for(stats)
      traits["max_mana"] = resource_values.fetch(:max_mana)
      traits["resource_name"] = resource_values.fetch(:name)
      traits["resource_formula"] = resource_values.fetch(:formula)
      traits["resource_die"] = resource_values.fetch(:die)
      traits["max_resource"] = resource_values.fetch(:max_resource)
      traits["current_mana"] = preserved_tracker_value(character.trait_set.current_mana, character.trait_set.max_mana, traits["max_mana"])
      traits["current_resource"] = preserved_tracker_value(character.trait_set.current_resource, character.trait_set.max_resource, traits["max_resource"])
    end

    {
      "level" => target_level,
      "stats" => stats,
      "skills" => skills,
      "traits" => traits,
      "hp_gain" => hp_gain,
      "hit_die_rolls" => [ level_up.hit_die_roll_one, level_up.hit_die_roll_two ],
      "stat_increase_type" => stat_increase_type,
      "subclass" => level_up.subclass_name.presence || character.subclass_name,
      "spell_tier" => spell_tier_for(target_level),
      "explanations" => applied_explanations(stats, hp_gain)
    }
  end

  private
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

    def stat_increase_quote
      if stat_increase_type == "key"
        "At levels 4, 8, 12, 16, and 20, increase one Key Stat by +1."
      elsif stat_increase_type == "any_two"
        "At level 20, increase any 2 different stats by +1."
      else
        "At levels 5, 9, 13, and 17, increase one Secondary Stat by +1."
      end
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
          message: "Max HP increases by #{hp_gain} (higher of #{level_up.hit_die_roll_one} and #{level_up.hit_die_roll_two} on #{character.trait_set&.hit_die || '1d6'}).",
          source_ref: "Chapter 3, Derived Values",
          quote: "HP Increase. Roll your Hit Die with advantage and increase your max HP by that much."
        }
      ]
      [ level_up.stat_name, level_up.second_stat_name ].compact_blank.each do |stat_name|
        explanations << {
          type: "applied",
          message: "#{stat_name.humanize} increases to #{stats.fetch(stat_name)}.",
          source_ref: "Chapter 3, Stat Increases",
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
