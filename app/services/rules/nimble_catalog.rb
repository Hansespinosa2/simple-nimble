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

      def class_for(name)
        data.fetch("classes")[name.to_s]
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

      def classes
        data.fetch("classes")
      end
    end
  end
end
