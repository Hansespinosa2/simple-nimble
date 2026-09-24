class StorySubclassChangeService
  MAX_STORY_NOTE_LENGTH = 1_000

  def self.call(character:, share:, approved_by:, current_subclass:, to_subclass:, story_note:, spell_choices: {})
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
      from_subclass = character.subclass_name
      spell_choice_ledger = character.spell_choice_ledger
      approved_spell_choices.each do |pool_name, selections_by_level|
        spell_choice_ledger[pool_name] ||= {}
        spell_choice_ledger[pool_name].merge!(selections_by_level)
      end

      character.with_approved_story_subclass_change(
        from_subclass:,
        to_subclass:,
        story_note: note,
        campaign: current_share.campaign,
        approved_by:
      ) do
        character.subclass_name = to_subclass
        character.spell_choices = spell_choice_ledger
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
          subclass_choices: approved_spell_choices,
          source_ref: story_rule.fetch("source_ref")
        )
      end
    end

    change
  end

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
