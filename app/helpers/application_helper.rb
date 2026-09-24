module ApplicationHelper
  def companion_size_level_requirements(rule)
    rule.fetch("minimum_level_by_size", {}).to_h
      .group_by { |_size, minimum_level| minimum_level.to_i }
      .sort
      .filter_map do |minimum_level, size_rules|
        next if minimum_level <= 1

        sizes = size_rules.map(&:first)
        requirement = sizes.one? ? "companion requires" : "companions require"
        "#{sizes.to_sentence} #{requirement} level #{minimum_level}."
      end
  end
end
