module CharactersHelper
  def status_badge_class(status)
    {
      "draft" => "badge badge-draft",
      "playable" => "badge badge-playable",
      "level_up" => "badge badge-level-up"
    }.fetch(status.to_s, "badge")
  end

  def signed_value(value)
    number = value.to_i
    number.positive? ? "+#{number}" : number.to_s
  end

  def stat_array_rules_summary
    Rules::NimbleCatalog.stat_arrays.map do |name, values|
      "#{name.humanize} #{values.map { |value| signed_value(value) }.join("/")}"
    end.join(" · ")
  end

  def stat_display_name(stat)
    { "strength" => "STR", "dexterity" => "DEX", "intelligence" => "INT", "will" => "WIL" }.fetch(stat.to_s, stat.to_s.humanize)
  end

  def skill_display_name(skill)
    skill.to_s.humanize
  end

  def armor_rule_caption(character)
    rules = character.character_class&.armor_rules.to_h
    equipment = character.equipped_armor_profiles.select { |item| character.equipment_armor_requirement_met?(item.fetch("rules")) }
    body_armor = equipment.find { |item| item.fetch("rules").fetch("kind") == "armor" }
    shields = equipment.select { |item| item.fetch("rules").fetch("kind") == "shield" }
    source_refs = []

    basis = if body_armor
      armor = body_armor.fetch("rules")
      source_refs << body_armor.fetch("source_ref")
      formula = armor.fetch("formula") == "dexterity" ? " + DEX#{" (max #{armor.fetch('dexterity_cap')})" if armor['dexterity_cap']}" : ""
      "#{body_armor.fetch('name')} #{armor.fetch('armor_value')}#{formula}"
    elsif rules.fetch("unarmored_formula", "dexterity") == "dexterity_plus_strength"
      source_refs << rules["source_ref"]
      "Unarmored DEX + STR"
    else
      source_refs << (rules["source_ref"] || "Core Rules 2.0.1, p. 33")
      "Unarmored DEX"
    end
    shields.each do |item|
      source_refs << item.fetch("source_ref")
      basis += " + #{item.fetch('name')} #{item.fetch('rules').fetch('armor_value')}"
    end
    effects = character.derived_feature_effects
    if effects.fetch("armor_multiplier", 1).to_i > 1 && body_armor.nil?
      basis += " ×2 while unarmored"
      source_refs << effects["armor_multiplier_source_ref"]
    end
    source_refs = source_refs.compact.uniq

    "#{basis} + origin · #{source_refs.join('; ')}"
  end

  def inventory_armor_effect(character, item)
    rules = item.armor_profile
    return unless rules

    if item.equipped?
      return "Equipped, but no Armor benefit until STR requirement is met" unless character.equipment_armor_requirement_met?(rules)

      "+#{equipment_armor_value_for_caption(character, rules)} Armor to total"
    else
      "+#{equipment_armor_value_for_caption(character, rules)} Armor if equipped"
    end
  end

  def inventory_armor_warnings(character, item)
    rules = item.armor_profile
    return unless rules

    warnings = []
    if rules["strength_requirement"].present? && character.stat_value("strength").to_i < rules.fetch("strength_requirement").to_i
      warnings << "Requires STR #{rules.fetch('strength_requirement')} (current STR #{character.stat_value('strength')}); the Armor benefit is not applied until the requirement is met."
    end
    if item.equipped? && rules.fetch("kind") == "armor" && !character.armor_proficient_with?(rules)
      warnings << "Not proficient with #{rules.fetch('proficiency')} armor: Defend while wearing it costs 1 additional action · Core Rules 2.0.1, p. 32."
    elsif item.equipped? && rules.fetch("kind") == "shield" && !character.armor_proficient_with?(rules)
      warnings << "This class has no shield proficiency listed; the parsed rules do not specify a separate shield penalty."
    end
    warnings
  end

  def equipment_armor_value_for_caption(character, rules)
    rules.fetch("kind") == "shield" ? rules.fetch("armor_value").to_i : character.equipment_armor_value(rules)
  end

  def starting_equipment_context(character)
    rules = Rules::NimbleCatalog.starting_equipment_rules
    if character.starting_equipment_choice == "starting_gold"
      "Starting gold replaces the class/background gear package and is tracked with carried inventory. #{rules.fetch('source_ref')}."
    else
      "#{rules.fetch('background_gear_note')} #{rules.fetch('background_gear_source_ref')}. This records the kit chosen at creation; current items are tracked below."
    end
  end

  def revision_event_class(event_type)
    {
      "level_up" => "timeline-dot timeline-dot-gold",
      "safe_rest" => "timeline-dot timeline-dot-green",
      "field_rest" => "timeline-dot timeline-dot-gold",
      "inventory_update" => "timeline-dot timeline-dot-blue",
      "game_update" => "timeline-dot timeline-dot-blue",
      "finalized" => "timeline-dot timeline-dot-green"
    }.fetch(event_type.to_s, "timeline-dot")
  end

  def rules_option_summary(record)
    return if record.blank?

    if record.respond_to?(:trait_summary)
      record.trait_summary
    elsif record.respond_to?(:description)
      record.description
    end
  end
end
