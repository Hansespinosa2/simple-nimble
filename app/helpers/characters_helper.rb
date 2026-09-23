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

  def stat_display_name(stat)
    { "strength" => "STR", "dexterity" => "DEX", "intelligence" => "INT", "will" => "WIL" }.fetch(stat.to_s, stat.to_s.humanize)
  end

  def skill_display_name(skill)
    skill.to_s.humanize
  end

  def armor_rule_caption(character)
    rules = character.character_class&.armor_rules.to_h
    source_ref = rules["source_ref"] || "Core Rules 2.0.1, p. 33"
    basis = if rules["formula"] == "dexterity_plus_strength"
      "Unarmored DEX + STR"
    elsif character.starting_equipment_choice == "starting_gold"
      "Unarmored DEX"
    else
      "Starting gear"
    end

    "#{basis} + origin · #{source_ref}"
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
