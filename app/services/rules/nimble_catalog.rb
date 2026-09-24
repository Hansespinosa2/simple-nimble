require "yaml"

module Rules
  class NimbleCatalog
    PATH = Rails.root.join("config", "rules", "nimble_v2_0_1.yml").freeze

    class << self
      def data
        @data ||= YAML.safe_load_file(PATH)
      end

      def reset!
        @data = nil
      end

      def version
        data.fetch("version")
      end

      def source(key)
        data.fetch("sources").fetch(key.to_s)
      end

      def derived_values
        data.fetch("derived_values")
      end

      def stat_increase_mechanic_for(type)
        derived_values.fetch("stat_increase_mechanics", {}).fetch(type.to_s, {})
      end

      def language_rules
        data.fetch("languages")
      end

      def class_language_grants_for(class_name, level)
        entries = class_language_rules_for(class_name)
        entries.select { |entry| level.to_i >= entry.fetch("level").to_i }.flat_map { |entry| entry.fetch("languages") }.uniq
      end

      def class_language_rules_for(class_name)
        language_rules.fetch("class_grants", {}).fetch(class_name.to_s, [])
      end

      def language_feature_choice(feature_name)
        language_rules.fetch("feature_language_choices", {})[feature_name.to_s]
      end

      def stats
        data.fetch("stats")
      end

      def stat_name_for_abbreviation(abbreviation)
        stats.find do |_name, definition|
          definition.fetch("abbreviation").casecmp?(abbreviation.to_s)
        end&.first
      end

      def skills
        data.fetch("skills")
      end

      def stat_arrays
        data.fetch("stat_arrays")
      end

      def condition_tracking
        data.fetch("condition_tracking")
      end

      def resting_rules
        data.fetch("resting")
      end

      def starting_equipment_rules
        data.fetch("starting_equipment")
      end

      def starting_gear_inventory_items(class_name)
        gear_names = Array(class_for(class_name).to_h.fetch("starting_gear", []))
        inventory_items = data.fetch("starting_gear_inventory").fetch("items")

        gear_names.map { |name| inventory_items.fetch(name.to_s).merge("name" => name) }
      end

      def starting_gear_inventory_slots(class_name)
        starting_gear_inventory_items(class_name).sum { |item| item.fetch("slots").to_i }
      end

      def equipment_armor_items
        data.fetch("equipment_armor").fetch("items")
      end

      def equipment_armor_item(name)
        equipment_armor_items[name.to_s]
      end

      def class_derived_effects(class_name)
        data.fetch("derived_effects", {}).fetch("classes", {}).fetch(class_name.to_s, {})
      end

      def class_for(name)
        data.fetch("classes")[name.to_s]
      end

      def class_resource_pool_for(class_name, pool_key)
        Array(class_for(class_name).to_h.dig("resource", "pools")).find do |pool|
          pool.fetch("key") == pool_key.to_s
        end
      end

      def story_based_subclasses_for(class_name)
        story_based_subclass_records_for(class_name).map { |subclass| subclass.fetch("name") }
      end

      def story_based_subclass_records_for(class_name)
        Array(class_for(class_name).to_h.fetch("story_based_subclasses", []))
      end

      def spell_tier_for(class_name, level)
        unlocks = class_for(class_name).to_h.fetch("spell_tier_unlocks", {})
        unlocks.select { |unlock_level, _tier| level.to_i >= unlock_level.to_i }.values.map(&:to_i).max.to_i
      end

      def stat_increase_for(class_name, level)
        schedule = class_for(class_name).to_h.fetch("stat_increases", {})
        schedule.each do |type, levels|
          return type if Array(levels).map(&:to_i).include?(level.to_i)
        end

        nil
      end

      def stat_increase_levels_for(class_name, type)
        Array(class_for(class_name).to_h.fetch("stat_increases", {}).fetch(type.to_s, [])).map(&:to_i)
      end

      def spell_school_choice_for(class_name)
        class_for(class_name).to_h.fetch("spell_school_choice", nil)
      end

      def progression_for(class_name)
        data.fetch("progression", {}).fetch(class_name.to_s, {})
      end

      def subclass_choice_level_for(class_name)
        progression_for(class_name)
          .fetch("features", {})
          .find { |_level, features| Array(features).include?("Subclass choice") }
          &.first
          &.to_i
      end

      def features_for(class_name, level)
        progression_for(class_name).fetch("features", {}).fetch(level.to_i, [])
      end

      def subclass_features_for(class_name, subclass_name, level)
        progression_for(class_name)
          .fetch("subclass_features", {})
          .fetch(subclass_name.to_s, {})
          .fetch(level.to_i, [])
      end

      def choice_pools_for(class_name, level)
        choice_pools_for_class(class_name).filter_map do |pool_name, definition|
          count = definition.to_h.fetch("choices", {}).fetch(level.to_i, nil)
          next if count.nil?

          definition.merge("name" => pool_name.to_s, "level" => level.to_i, "count" => count.to_i)
        end
      end

      def choice_pool_for(class_name, pool_name)
        choice_pools_for_class(class_name).fetch(pool_name.to_s, nil)
      end

      def feature_choice_effects_for(class_name, selections_by_pool)
        selections_by_pool.to_h.each_with_object({}) do |(pool_name, selections), effects|
          option_effects = choice_pool_for(class_name, pool_name).to_h.fetch("option_effects", {})
          Array(selections).each do |selection|
            option_effects.fetch(selection.to_s, {}).to_h.each do |effect_name, values|
              effects[effect_name] ||= {}
              values.to_h.each do |key, value|
                effects[effect_name][key] = effects[effect_name].fetch(key, 0).to_i + value.to_i
              end
            end
          end
        end
      end

      def spell_choice_pools_for(class_name, level)
        data.fetch("spell_choice_pools", {}).fetch(class_name.to_s, {}).filter_map do |pool_name, definition|
          count = definition.to_h.fetch("choices", {}).fetch(level.to_i, nil)
          next if count.nil?

          definition.merge("name" => pool_name.to_s, "level" => level.to_i, "count" => count.to_i)
        end
      end

      def story_subclass_spell_choice_pools_for(class_name, subclass_name, level)
        data.fetch("story_subclass_spell_choice_pools", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, {})
          .filter_map do |pool_name, definition|
            count = definition.to_h.fetch("choices", {}).fetch(level.to_i, nil)
            next if count.nil?

            max_tier = definition.to_h.fetch("maximum_tier_by_level", {}).fetch(level.to_i, nil)
            definition.merge(
              "name" => pool_name.to_s,
              "level" => level.to_i,
              "count" => count.to_i,
              "source_quote" => definition.to_h.fetch("source_quote_by_level", {}).fetch(level.to_i, definition.to_h.fetch("source_quote", nil)),
              "max_tier" => max_tier,
              "story_subclass" => subclass_name.to_s
            )
          end
      end

      def story_subclass_feature_choice_pools_for(class_name, subclass_name, level)
        story_subclass_feature_choice_pool_rules_for(class_name, subclass_name)
          .filter_map do |pool_name, definition|
            count = definition.to_h.fetch("choices", {}).fetch(level.to_i, nil)
            next if count.nil?

            definition.merge("name" => pool_name.to_s, "level" => level.to_i, "count" => count.to_i, "story_subclass" => subclass_name.to_s)
          end
      end

      def story_subclass_feature_choice_pool_rules_for(class_name, subclass_name)
        data.fetch("story_subclass_feature_choice_pools", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, {})
      end

      def story_subclass_replaced_feature_choice_pools_for(class_name, subclass_name)
        story_subclass_feature_choice_pool_rules_for(class_name, subclass_name)
          .values
          .flat_map { |definition| Array(definition.to_h["replaces_feature_choice_pools"]) }
          .uniq
      end

      def story_subclass_replaced_progression_features_for(class_name, subclass_name)
        explicit_replacements = data.fetch("story_subclass_replaced_progression_features", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, [])
        choice_pool_replacements = story_subclass_feature_choice_pool_rules_for(class_name, subclass_name)
          .values
          .flat_map { |definition| Array(definition.to_h["replaces_progression_features"]) }
        (Array(explicit_replacements) + choice_pool_replacements).uniq
      end

      def story_subclass_companion_rule_for(class_name, subclass_name)
        data.fetch("story_subclass_companions", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, nil)
      end

      def story_subclass_companion_abilities_for(class_name, subclass_name)
        story_subclass_companion_rule_for(class_name, subclass_name).to_h.fetch("abilities", {})
      end

      def background_spell_choice_for(background_name)
        data.fetch("background_spell_choices", {}).fetch(background_name.to_s, nil)
      end

      def ancestry_resource_pools_for(ancestry_name)
        data.fetch("ancestry_resource_pools", {}).fetch(ancestry_name.to_s, [])
      end

      def story_subclass_resource_pools_for(class_name, subclass_name)
        data.fetch("story_subclass_resource_pools", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, [])
      end

      def story_subclass_resource_pool_for(class_name, subclass_name, pool_key)
        story_subclass_resource_pools_for(class_name, subclass_name).find do |pool|
          pool.fetch("key") == pool_key.to_s
        end
      end

      def story_subclass_resource_pool_replacements_for(class_name, subclass_name)
        data.fetch("story_subclass_resource_pool_replacements", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, [])
      end

      def story_subclass_spell_restrictions_for(class_name, subclass_name)
        data.fetch("story_subclass_spell_restrictions", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, [])
      end

      def story_subclass_spell_restriction_source_ref_for(class_name, subclass_name)
        data.fetch("story_subclass_spell_restriction_source_refs", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, nil)
      end

      def story_subclass_spell_grants_for(class_name, subclass_name)
        data.fetch("story_subclass_spell_grants", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, [])
      end

      def story_subclass_spell_choice_school_extensions_for(class_name, subclass_name)
        data.fetch("story_subclass_spell_choice_school_extensions", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, [])
      end

      def story_subclass_weapon_rules_for(class_name, subclass_name)
        data.fetch("story_subclass_weapon_rules", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, {})
      end

      def story_subclass_feature_notes_for(class_name, subclass_name)
        data.fetch("story_subclass_feature_notes", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, [])
      end

      def story_subclass_feature_note_for(class_name, subclass_name, feature_name)
        story_subclass_feature_notes_for(class_name, subclass_name).find do |note|
          note.fetch("name") == feature_name.to_s
        end
      end

      def story_subclass_initiative_features_for(class_name, subclass_name)
        data.fetch("story_subclass_initiative_features", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, [])
      end

      def story_subclass_feature_unlock_level_for(class_name, subclass_name, feature_name)
        class_name = class_name.to_s
        subclass_name = subclass_name.to_s
        feature_name = feature_name.to_s

        feature = story_subclass_feature_notes_for(class_name, subclass_name).find do |note|
          note.fetch("name") == feature_name
        end
        return feature.fetch("unlock_level").to_i if feature

        feature = story_subclass_initiative_features_for(class_name, subclass_name).find do |entry|
          entry.fetch("name") == feature_name
        end
        return feature.fetch("unlock_level").to_i if feature&.key?("unlock_level")

        unlock_level = progression_for(class_name)
          .fetch("subclass_features", {})
          .fetch(subclass_name, {})
          .find { |_unlock_level, features| Array(features).include?(feature_name) }
          &.first
        unlock_level&.to_i
      end

      def initiative_resource_grant_for(class_name, subclass_name, level)
        class_name = class_name.to_s
        subclass_name = subclass_name.to_s
        grants = Array(data.fetch("initiative_resource_grants", {}).fetch(class_name, {}).fetch(subclass_name, []))

        grants.find do |grant|
          unlock_level = story_subclass_feature_unlock_level_for(class_name, subclass_name, grant.fetch("feature_name"))
          unlock_level.present? && level.to_i >= unlock_level
        end
      end

      def story_subclass_empowered_orders_for(class_name, subclass_name)
        data.fetch("story_subclass_empowered_orders", {})
          .fetch(class_name.to_s, {})
          .fetch(subclass_name.to_s, {})
      end

      def spell_auto_grants_for(class_name, level)
        data.fetch("spell_choice_auto_grants", {}).fetch(class_name.to_s, {}).each_with_object([]) do |(grant_level, grants), result|
          result.concat(Array(grants)) if grant_level.to_i <= level.to_i
        end.uniq
      end

      def derived_effects_for(class_name, subclass_name, level)
        derived_effects = data.fetch("derived_effects", {})
        schedules = [
          derived_effects.fetch("classes", {}).fetch(class_name.to_s, {}),
          derived_effects.fetch("subclasses", {}).fetch(class_name.to_s, {}).fetch(subclass_name.to_s, {})
        ]
        effects = {}
        schedules.each do |schedule|
          schedule.each do |effect_level, effect_values|
            next if effect_level.to_i > level.to_i

            effects.merge!(effect_values) do |key, previous, current|
              if %w[speed_modifier max_hp_modifier max_wounds_modifier].include?(key.to_s)
                previous.to_i + current.to_i
              elsif key.to_s == "resource_max_modifiers"
                (previous.to_h.keys | current.to_h.keys).index_with do |resource_key|
                  previous.to_h.fetch(resource_key, 0).to_i + current.to_h.fetch(resource_key, 0).to_i
                end
              else
                current
              end
            end
          end
        end
        effects
      end

      def classes
        data.fetch("classes")
      end

      private
        def choice_pools_for_class(class_name)
          data.fetch("choice_pools", {}).fetch(class_name.to_s, {})
        end
    end
  end
end
