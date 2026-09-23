class LevelUpPlanner
  attr_reader :character, :level_up

  def initialize(character, level_up)
    @character = character
    @level_up = level_up
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

  def issues
    result = []
    result << issue("This character is not in a playable state.", "Chapter 4, Character Lifecycle", "Level-up begins from a PlayableValid character.") unless character.playable? || character.level_up_in_progress?
    result << issue("Resolve the character's creation checks before leveling up.", "Chapter 3, Character Creation", "A level-up can only begin from a legal character state.") unless character.creation_issues.empty?
    result << issue("This character is already at the maximum level.", "Chapter 3, Character Progression", "Characters advance from level 1 through level 20.") if character.level.to_i >= 20
    result << issue("This level-up has already been finalized.", "Chapter 4, Character Lifecycle", "A finalized transition cannot be applied twice.") if level_up.finalized?
    result << issue("Level-up must start from the character's current level.", "Chapter 4, Character Lifecycle", "A transition records the exact level it advances from.") unless level_up.from_level.to_i == character.level.to_i
    result << issue("Level-up must advance exactly one level.", "Chapter 3, Character Progression", "Level-up is an explicit one-level transition.") unless target_level == character.level.to_i + 1

    if level_up.skill_name.blank?
      result << issue("Choose one skill to improve.", "Chapter 3, Skills", "Each level grants 1 skill point.")
    elsif !Character::SKILL_NAMES.include?(level_up.skill_name)
      result << issue("#{level_up.skill_name.to_s.humanize} is not a recognized skill.", "Chapter 3, Skills", "Choose one of the ten skills listed in the character rules.")
    elsif !skill_options.include?(level_up.skill_name)
      result << issue("#{level_up.skill_name.to_s.humanize} is already at the +12 skill maximum.", "Chapter 3, Skills", "Skill values cannot exceed +12.")
    end

    if stat_increase_type.present?
      if level_up.stat_name.blank?
        result << issue("Choose a #{stat_increase_type} stat to increase.", "Chapter 3, Stat Increases", stat_increase_quote)
      elsif !stat_options.include?(level_up.stat_name)
        result << issue("#{level_up.stat_name.to_s.humanize} is not eligible for this level's stat increase.", "Chapter 3, Stat Increases", stat_increase_quote)
      elsif character.stat_value(level_up.stat_name) >= 5
        result << issue("#{level_up.stat_name.to_s.humanize} is already at the +5 stat maximum.", "Chapter 3, Stats", "Stats cannot exceed +5.")
      end
    elsif level_up.stat_name.present?
      result << issue("No stat increase is scheduled at level #{target_level}.", "Chapter 3, Stat Increases", "Stat increases occur at scheduled class progression levels.")
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
      "max_hit_dice" => character.trait_set&.max_hit_dice.to_i,
      "current_hit_dice" => character.trait_set&.current_hit_dice.to_i,
      "initiative" => character.trait_set&.initiative.to_i,
      "armor" => character.trait_set&.armor.to_i,
      "inventory_slots" => character.trait_set&.inventory_slots.to_i
    }

    if level_up.stat_name.present? && stat_options.include?(level_up.stat_name)
      stats[level_up.stat_name] += 1
      Character::SKILL_NAMES.each do |skill|
        skills[skill] += 1 if Character::SKILL_TO_STAT.fetch(skill) == level_up.stat_name
      end
    end

    skills[level_up.skill_name] += 1 if level_up.skill_name.present? && skills.key?(level_up.skill_name)

    hp_gain = hit_die_size + [ stats.fetch("strength"), 0 ].max
    if character.trait_set
      traits["max_hp"] += hp_gain
      traits["current_hp"] = traits["max_hp"] if character.trait_set.current_hp.to_i >= character.trait_set.max_hp.to_i
      traits["max_hit_dice"] = target_level + (character.ancestry&.max_hit_dice_modifier || 0)
      traits["current_hit_dice"] = [ character.trait_set.current_hit_dice.to_i + 1, traits["max_hit_dice"] ].min
      traits["initiative"] = stats.fetch("dexterity") + (character.ancestry&.initiative_modifier || 0)
      traits["armor"] = stats.fetch("dexterity") + (character.ancestry&.armor_modifier || 0)
      traits["inventory_slots"] = Character::BASE_INVENTORY_SLOTS + stats.fetch("strength")
    end

    {
      "level" => target_level,
      "stats" => stats,
      "skills" => skills,
      "traits" => traits,
      "hp_gain" => hp_gain,
      "stat_increase_type" => stat_increase_type,
      "spell_tier" => spell_tier_for(target_level),
      "explanations" => applied_explanations(stats, hp_gain)
    }
  end

  private
    def hit_die_size
      hit_die = character.trait_set&.hit_die.presence || character.character_class&.hit_die
      hit_die.to_s.split("d").last.to_i.nonzero? || 6
    end

    def spell_tier_for(level)
      unlocks = {
        "Mage" => [ 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9 ],
        "Oathsworn" => [ 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7, 7 ],
        "Shadowmancer" => [ 0, 1, 1, 1, 1, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7 ],
        "Shepherd" => [ 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 6, 6, 7, 7, 8, 8, 9, 9 ],
        "Stormshifter" => [ 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9 ],
        "Songweaver" => [ 0, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 0, 0, 0, 0 ]
      }
      unlocks.fetch(character.character_class&.name, Array.new(20, 0)).fetch(level.to_i - 1, 0)
    end

    def stat_increase_quote
      if stat_increase_type == "key"
        "At levels 4, 8, 12, 16, and 20, increase one Key Stat by +1."
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
          message: "Max HP increases by #{hp_gain} (#{character.trait_set&.hit_die || '1d6'} preview plus STR).",
          source_ref: "Chapter 3, Derived Values",
          quote: "HP on level-up: roll Hit Die with advantage + STR."
        }
      ]
      if level_up.stat_name.present?
        explanations << {
          type: "applied",
          message: "#{level_up.stat_name.humanize} increases to #{stats.fetch(level_up.stat_name)}.",
          source_ref: "Chapter 3, Stat Increases",
          quote: stat_increase_quote
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
