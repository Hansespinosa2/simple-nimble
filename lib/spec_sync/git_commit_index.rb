require "open3"

module SpecSync
  class GitCommitIndex
    REFERENCE_PATTERN = /\bS-\d{2}:AC-\d+\b/

    def initialize(root: Rails.root)
      @root = root
    end

    def links_by_reference
      @links_by_reference ||= begin
        links = Hash.new { |hash, key| hash[key] = [] }

        commit_pairs.each do |sha, message|
          summary = message.lines.first.to_s.strip
          message.scan(REFERENCE_PATTERN).uniq.each do |reference|
            links[reference] << CommitLink.new(sha:, summary:)
          end
        end

        links.transform_values(&:freeze)
      end
    end

    private

    attr_reader :root

    def commit_pairs
      stdout, stderr, status = Open3.capture3(
        "git", "--no-pager", "log", "--format=%H%x00%B%x1e",
        chdir: root.to_s
      )
      raise "Unable to read git history: #{stderr}" unless status.success?

      stdout.split("\x1e").filter_map do |record|
        next unless record.include?("\x00")

        sha, message = record.sub(/\A\n+/, "").split("\x00", 2)
        [sha, message.to_s]
      end
    end
  end
end
