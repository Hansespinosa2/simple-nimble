require "pathname"

module SpecSync
  class Catalog
    SPEC_GLOB = "specs/app/[0-9][0-9]-*.md"
    ACCEPTANCE_CRITERIA_HEADING = "## 8. Acceptance criteria"

    def initialize(root: Rails.root)
      @root = Pathname(root)
    end

    def specs
      spec_paths.map { |path| parse_spec(path) }
    end

    def references
      specs.flat_map(&:acceptance_criteria).map(&:reference)
    end

    private

    attr_reader :root

    def spec_paths
      Dir[root.join(SPEC_GLOB)].sort.map { |path| Pathname(path) }
    end

    def parse_spec(path)
      content = path.read
      spec_id = extract_spec_id(path)
      title = content[/^# Specification:\s+(.+)$/, 1]
      status = content[/^> \*\*Status:\*\*\s+(.+)$/, 1]

      raise "Missing specification title in #{path}" if title.nil?
      raise "Missing specification status in #{path}" if status.nil?

      acceptance_criteria = parse_acceptance_criteria(content, spec_id)

      SpecDocument.new(
        id: spec_id,
        title: title.strip,
        status: status.strip,
        path: path.relative_path_from(root).to_s,
        acceptance_criteria:
      )
    end

    def extract_spec_id(path)
      basename = path.basename.to_s
      prefix = basename[/\A(\d{2})-/, 1]
      raise "Cannot derive spec ID from #{basename}" if prefix.nil?

      "S-#{prefix}"
    end

    def parse_acceptance_criteria(content, spec_id)
      section = content.split(/^#{Regexp.escape(ACCEPTANCE_CRITERIA_HEADING)}$/).last
      raise "Missing acceptance criteria section for #{spec_id}" if section.nil?

      table_lines = section.lines.drop_while { |line| !line.start_with?("|") }
      table_lines = table_lines.take_while { |line| line.start_with?("|") }
      headers, rows = parse_markdown_table(table_lines)

      rows.map do |row|
        criterion_id = row.fetch("ID").strip
        AcceptanceCriterion.new(
          reference: Reference.new(spec_id:, criterion_id:),
          type: row.fetch("Type").strip,
          criterion: row.fetch("Criterion").strip,
          spec_confidence: normalize_status(row.fetch("Status"))
        )
      end
    end

    def parse_markdown_table(lines)
      raise "Expected markdown table lines" if lines.length < 2

      headers = split_markdown_row(lines.first)
      rows = lines.drop(2).reject { |line| line.strip.empty? }.map do |line|
        values = split_markdown_row(line)
        headers.zip(values).to_h
      end

      [ headers, rows ]
    end

    def split_markdown_row(line)
      line.split("|").drop(1).map(&:strip).tap(&:pop)
    end

    def normalize_status(value)
      value.strip.delete_prefix("`").delete_suffix("`")
    end
  end
end
