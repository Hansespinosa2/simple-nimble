module Rules
  module StorySubclassChoiceGroups
    module_function

    def conflicts_for(character:, definitions:, feature_choices:, spell_choices:)
      definitions.filter_map do |name, definition|
        selections = selections_for(character:, definition:, feature_choices:, spell_choices:)
        duplicates = selections.tally.filter_map { |selection, count| selection if count > 1 }
        { group: name, selections: duplicates } if duplicates.any?
      end
    end

    def selections_for(character:, definition:, feature_choices: {}, spell_choices: {})
      prefix = definition.fetch("prefix")
      selections = []
      if definition.fetch("include_recorded_prefixed_feature_choices", false)
        selections.concat(prefixed_selections(character.recorded_feature_choices.values.flatten, prefix))
      end
      if definition.fetch("include_current_prefixed_feature_choices", false)
        selections.concat(prefixed_selections(nested_values(feature_choices), prefix))
      end
      Array(definition.fetch("recorded_feature_choice_pools", [])).each do |pool_name|
        selections.concat(character.recorded_feature_choices.fetch(pool_name, []))
      end
      if definition.fetch("include_recorded_spell_choices", false)
        selections.concat(character.recorded_spell_choices.values.flatten)
      end
      if definition.fetch("include_current_spell_choices", false)
        selections.concat(nested_values(spell_choices))
      end
      if definition.fetch("include_known_sheet_spells", false)
        known_spells = character.sheet_spells.pluck(:name)
        known_spells -= character.story_granted_spell_names if definition.fetch("exclude_story_granted_spells", false)
        selections.concat(known_spells)
      end

      selections.map(&:to_s).reject(&:blank?)
    end

    def nested_values(value)
      case value
      when Hash
        value.values.flat_map { |nested| nested_values(nested) }
      when Array
        value.flat_map { |nested| nested_values(nested) }
      else
        [ value.to_s ]
      end
    end
    private_class_method :nested_values

    def prefixed_selections(selections, prefix)
      Array(selections).filter_map do |selection|
        selection.to_s.delete_prefix(prefix) if selection.to_s.start_with?(prefix)
      end
    end
    private_class_method :prefixed_selections
  end
end
