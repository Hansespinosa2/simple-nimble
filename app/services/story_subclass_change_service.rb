class StorySubclassChangeService
  MAX_STORY_NOTE_LENGTH = 1_000

  def self.call(character:, share:, approved_by:, current_subclass:, to_subclass:, story_note:, spell_choices: {}, feature_choices: {}, companion_name: nil, companion_size: nil)
    note = story_note.to_s.strip
    raise ArgumentError, "Add a story note explaining why the subclass changes." if note.blank?
    raise ArgumentError, "Story notes must be #{MAX_STORY_NOTE_LENGTH} characters or fewer." if note.length > MAX_STORY_NOTE_LENGTH

    change = nil
    character.with_lock do
      current_share = CharacterShare.find_by(id: share.id, character_id: character.id, campaign_id: share.campaign_id)
      raise ArgumentError, "This shared sheet is no longer available." unless current_share&.permission == "read"
      raise ArgumentError, "Only this campaign's GM can approve a story subclass change." unless current_share.campaign.gm?(approved_by)
      raise ArgumentError, "This sheet changed since you opened it. Refresh and try again." unless character.subclass_name == current_subclass.to_s
      raise ArgumentError, "A story-based subclass can only replace an existing subclass." if character.subclass_name.blank?
      raise ArgumentError, "Choose a different subclass from the one currently recorded." if character.subclass_name == to_subclass.to_s

      story_rule = character.character_class&.story_based_subclass_rule(to_subclass)
      raise ArgumentError, "#{to_subclass} is not a story-based subclass for this character's class." unless story_rule

      approved_spell_choices = validate_spell_choices!(character, to_subclass, spell_choices)
      approved_feature_choices = validate_feature_choices!(character, to_subclass, feature_choices)
      validate_spellblade_choice_conflicts!(character, to_subclass, approved_feature_choices, approved_spell_choices)
      approved_companion = validate_companion!(character, to_subclass, companion_name:, companion_size:)
      replaced_feature_pools = Rules::NimbleCatalog.story_subclass_replaced_feature_choice_pools_for(character.character_class&.name, to_subclass)
      replaced_resource_pool_keys = Rules::NimbleCatalog.story_subclass_resource_pool_replacements_for(character.character_class&.name, to_subclass)
      replaced_spell_names = Rules::NimbleCatalog.story_subclass_spell_restrictions_for(character.character_class&.name, to_subclass) & character.spells.pluck(:name)
      replaced_resource_pools = Array(character.trait_set&.resource_tracks).map(&:to_h).select do |track|
        replaced_resource_pool_keys.include?(track["key"])
      end.index_by { |track| track.fetch("key") }
      feature_choice_ledger = character.feature_choice_ledger
      reconciled_pool_names = approved_feature_choices.keys | replaced_feature_pools
      replaced_feature_choices = feature_choice_ledger.slice(*reconciled_pool_names).reject { |_pool_name, selections| selections.blank? }
      choice_sources = story_choice_source_refs(
        character,
        to_subclass,
        approved_spell_choices,
        approved_feature_choices,
        approved_companion,
        replaced_feature_choices,
        replaced_resource_pools,
        replaced_spell_names
      )
      approved_subclass_choices = {
        "spell_choices" => approved_spell_choices,
        "feature_choices" => approved_feature_choices,
        "replaced_feature_choices" => replaced_feature_choices,
        "replaced_resource_pools" => replaced_resource_pools,
        "replaced_spells" => replaced_spell_names,
        "companion" => approved_companion,
        "source_refs" => choice_sources
      }.reject { |_key, value| value.blank? }

      from_subclass = character.subclass_name
      spell_choice_ledger = character.spell_choice_ledger
      approved_spell_choices.each do |pool_name, selections_by_level|
        spell_choice_ledger[pool_name] ||= {}
        spell_choice_ledger[pool_name].merge!(selections_by_level)
      end
      feature_choice_ledger.except!(*replaced_feature_pools)
      approved_feature_choices.each do |pool_name, selections_by_level|
        feature_choice_ledger[pool_name] ||= {}
        feature_choice_ledger[pool_name].delete("legacy")
        feature_choice_ledger[pool_name].merge!(selections_by_level)
      end

      character.with_approved_story_subclass_change(
        from_subclass:,
        to_subclass:,
        story_note: note,
        campaign: current_share.campaign,
        approved_by:
      ) do
        character.subclass_name = to_subclass
        character.bonescythe_summoned = false unless to_subclass == "Reaver"
        character.spells = character.spells.where.not(name: replaced_spell_names) if replaced_spell_names.present?
        character.spell_choices = spell_choice_ledger
        character.feature_choices = feature_choice_ledger if approved_feature_choices.present?
        character.subclass_choices = approved_subclass_choices
        character.save!

        revision = character.record_revision!(
          event_type: "story_subclass_change",
          summary: "#{approved_by.display_name} approved #{from_subclass} → #{to_subclass}. Story: #{note}",
          from_level: character.level,
          to_level: character.level
        )
        change = character.story_subclass_changes.create!(
          campaign: current_share.campaign,
          approved_by_account: approved_by,
          character_revision: revision,
          from_subclass:,
          to_subclass:,
          story_note: note,
          subclass_choices: approved_subclass_choices,
          source_ref: story_rule.fetch("source_ref")
        )
      end
    end

    change
  end

  def self.validate_feature_choices!(character, subclass_name, raw_choices)
    expected_pools = character.story_subclass_feature_choice_pools_through(subclass_name:, level: character.level)
    submitted = raw_choices.respond_to?(:to_unsafe_h) ? raw_choices.to_unsafe_h : raw_choices.to_h
    submitted = submitted.stringify_keys
    allowed_pool_names = expected_pools.map { |pool| pool.fetch("name") }.uniq
    unexpected_pools = submitted.keys - allowed_pool_names
    if unexpected_pools.any?
      raise ArgumentError, "#{unexpected_pools.join(', ')} is not a choice granted by #{subclass_name}."
    end

    expected_pools.group_by { |pool| pool.fetch("name") }.each_with_object({}) do |(pool_name, pools), normalized|
      level_values = submitted.fetch(pool_name, {}).to_h.stringify_keys
      expected_levels = pools.map { |pool| pool.fetch("level").to_s }
      unexpected_levels = level_values.keys - expected_levels
      if unexpected_levels.any?
        raise ArgumentError, "#{pool_name} is not granted at level #{unexpected_levels.join(', ')}."
      end

      selections_by_level = pools.to_h do |pool|
        level = pool.fetch("level").to_s
        selections = Array(level_values[level]).compact_blank.map(&:to_s)
        count = pool.fetch("count").to_i
        if selections.length != count
          raise ArgumentError, "Choose #{count} option#{count == 1 ? '' : 's'} for #{pool_name} at level #{level}."
        end

        invalid = selections - Array(pool.fetch("options"))
        if invalid.any?
          raise ArgumentError, "#{invalid.join(', ')} is not a legal #{pool_name} choice at level #{level}."
        end

        prior_by_level = character.feature_choice_ledger.fetch(pool_name, {})
        replaced_levels = expected_levels + [ "legacy" ]
        prior_other_levels = prior_by_level.reject { |prior_level, _| replaced_levels.include?(prior_level) }.values.flatten
        repeated = selections & prior_other_levels
        if repeated.any?
          raise ArgumentError, "#{repeated.join(', ')} is already selected at another #{pool_name} level."
        end

        [ level, selections ]
      end

      repeated = selections_by_level.values.flatten.tally.select { |_selection, count| count > 1 }.keys
      if repeated.any?
        raise ArgumentError, "Choose distinct options for #{pool_name}."
      end

      normalized[pool_name] = selections_by_level
    end
  end
  private_class_method :validate_feature_choices!

  def self.validate_companion!(character, subclass_name, companion_name:, companion_size:)
    rule = character.story_subclass_companion_rule(subclass_name)
    name = companion_name.to_s.strip
    size = companion_size.to_s
    if rule.blank?
      raise ArgumentError, "This story-based subclass does not grant a companion choice." if name.present? || size.present?

      return {}
    end

    if size.blank? || !Array(rule.fetch("sizes")).include?(size)
      raise ArgumentError, "Choose a companion size from #{Array(rule.fetch('sizes')).to_sentence}."
    end
    minimum_level = rule.fetch("minimum_level_by_size", {}).fetch(size, 1).to_i
    if character.level.to_i < minimum_level
      raise ArgumentError, "A #{size} companion requires level #{minimum_level}."
    end
    raise ArgumentError, "Name the animal companion." if name.blank?
    if name.length > rule.fetch("name_max_length").to_i
      raise ArgumentError, "The companion name must be #{rule.fetch('name_max_length')} characters or fewer."
    end

    { "size" => size, "name" => name }
  end
  private_class_method :validate_companion!

  def self.story_choice_source_refs(character, subclass_name, spell_choices, feature_choices, companion, replaced_feature_choices, replaced_resource_pools, replaced_spell_names)
    source_refs = {}
    unless spell_choices.empty?
      pools = character.story_subclass_spell_choice_pools_through(subclass_name:).index_by { |pool| pool.fetch("name") }
      source_refs["spell_choices"] = spell_choices.keys.index_with { |pool_name| pools.fetch(pool_name).fetch("source_ref") }
    end
    unless feature_choices.empty?
      pools = character.story_subclass_feature_choice_pools_through(subclass_name:).index_by { |pool| pool.fetch("name") }
      source_refs["feature_choices"] = feature_choices.keys.index_with do |pool_name|
        pool = pools.fetch(pool_name)
        [ pool.fetch("source_ref"), pool.fetch("story_source_ref") ].compact.uniq
      end
    end
    if companion.present?
      source_refs["companion"] = [ character.story_subclass_companion_rule(subclass_name).fetch("source_ref") ]
    end
    unless replaced_feature_choices.empty?
      source_refs["replaced_feature_choices"] = replaced_feature_choices.keys.index_with do |pool_name|
        Rules::NimbleCatalog.choice_pool_for(character.character_class&.name, pool_name).to_h.fetch("source_ref", character.character_class&.source_reference)
      end
    end
    unless replaced_resource_pools.empty?
      source_refs["replaced_resource_pools"] = replaced_resource_pools.keys.index_with do |pool_key|
        replaced_resource_pools.fetch(pool_key).fetch("source_ref", character.character_class&.source_reference)
      end
    end
    unless replaced_spell_names.empty?
      source_refs["replaced_spells"] = replaced_spell_names.index_with do |_spell_name|
        Rules::NimbleCatalog.story_subclass_spell_restriction_source_ref_for(character.character_class&.name, subclass_name)
      end
    end
    source_refs
  end
  private_class_method :story_choice_source_refs

  def self.validate_spellblade_choice_conflicts!(character, subclass_name, feature_choices, spell_choices)
    return unless character.character_class&.name == "Commander" && subclass_name == "Spellblade"

    selections = feature_choices.values.flat_map { |levels| levels.values.flatten }
    order_selections = selections.filter_map { |selection| selection.delete_prefix("Order: ") if selection.start_with?("Order: ") }
    prior_orders = character.recorded_feature_choices.fetch("Commander's Orders", [])
    repeated_orders = order_selections & prior_orders
    if repeated_orders.any? || order_selections.uniq.length != order_selections.length
      raise ArgumentError, "Choose a different Commander’s Order; an Order can only be selected once."
    end

    selected_spells = selections.filter_map { |selection| selection.delete_prefix("Spell: ") if selection.start_with?("Spell: ") }
    selected_spells.concat(spell_choices.values.flat_map { |levels| levels.values.flatten })
    previously_known = character.sheet_spells.pluck(:name)
    repeated_spells = (selected_spells & previously_known) | selected_spells.tally.select { |_spell, count| count > 1 }.keys
    return if repeated_spells.empty?

    raise ArgumentError, "Choose a different spell for each Arcane Command and Deep Knowledge choice (#{repeated_spells.join(', ')} is already selected)."
  end
  private_class_method :validate_spellblade_choice_conflicts!

  def self.validate_spell_choices!(character, subclass_name, raw_choices)
    expected_pools = character.story_subclass_spell_choice_pools_through(subclass_name:, level: character.level)
    submitted = raw_choices.respond_to?(:to_unsafe_h) ? raw_choices.to_unsafe_h : raw_choices.to_h
    submitted = submitted.stringify_keys
    allowed_pool_names = expected_pools.map { |pool| pool.fetch("name") }.uniq
    unexpected_pools = submitted.keys - allowed_pool_names
    if unexpected_pools.any?
      raise ArgumentError, "#{unexpected_pools.join(', ')} is not a choice granted by #{subclass_name}."
    end

    expected_pools.group_by { |pool| pool.fetch("name") }.each_with_object({}) do |(pool_name, pools), normalized|
      level_values = submitted.fetch(pool_name, {}).to_h.stringify_keys
      expected_levels = pools.map { |pool| pool.fetch("level").to_s }
      unexpected_levels = level_values.keys - expected_levels
      if unexpected_levels.any?
        raise ArgumentError, "#{pool_name} is not granted at level #{unexpected_levels.join(', ')}."
      end

      selections_by_level = pools.to_h do |pool|
        level = pool.fetch("level").to_s
        selections = Array(level_values[level]).compact_blank.map(&:to_s)
        count = pool.fetch("count").to_i
        if selections.length != count
          raise ArgumentError, "Choose #{count} option#{count == 1 ? '' : 's'} for #{pool_name} at level #{level}."
        end

        invalid = selections - Array(pool.fetch("options"))
        if invalid.any?
          raise ArgumentError, "#{invalid.join(', ')} is not a legal #{pool_name} choice at level #{level}."
        end

        [ level, selections ]
      end

      repeated = selections_by_level.values.flatten.tally.select { |_selection, count| count > 1 }.keys
      if repeated.any?
        raise ArgumentError, "Choose a different spell for each #{pool_name} feature."
      end

      normalized[pool_name] = selections_by_level
    end
  end
  private_class_method :validate_spell_choices!
end
