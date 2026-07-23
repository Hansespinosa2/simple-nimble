module SpecSync
  CriterionStatus = Data.define(
    :reference,
    :spec_title,
    :spec_status,
    :spec_path,
    :type,
    :criterion,
    :spec_confidence,
    :implementation_status,
    :manual_status,
    :commit_links
  )

  class Tracker
    def initialize(catalog: Catalog.new, status_store: StatusStore.new, git_commit_index: GitCommitIndex.new)
      @catalog = catalog
      @status_store = status_store
      @git_commit_index = git_commit_index
    end

    def criterion_statuses(filter: nil)
      normalized_filter = filter.to_s.strip
      catalog.specs.flat_map do |spec|
        spec.acceptance_criteria.filter_map do |criterion|
          status_row_for(spec:, criterion:, filter: normalized_filter)
        end
      end
    end

    def validate!
      status_store.validate!(valid_references: catalog.references.map(&:to_s).to_set)
      true
    end

    private

    attr_reader :catalog, :status_store, :git_commit_index

    def status_row_for(spec:, criterion:, filter:)
      return nil unless matches_filter?(spec:, criterion:, filter:)

      manual_status = status_store.manual_status(criterion.reference)
      commit_links = git_commit_index.links_by_reference.fetch(criterion.reference.to_s, [])
      implementation_status = resolve_implementation_status(manual_status:, commit_links:)

      CriterionStatus.new(
        reference: criterion.reference,
        spec_title: spec.title,
        spec_status: spec.status,
        spec_path: spec.path,
        type: criterion.type,
        criterion: criterion.criterion,
        spec_confidence: criterion.spec_confidence,
        implementation_status:,
        manual_status:,
        commit_links:
      )
    end

    def matches_filter?(spec:, criterion:, filter:)
      return true if filter.empty?

      filter == spec.id || filter == criterion.reference.to_s
    end

    def resolve_implementation_status(manual_status:, commit_links:)
      return manual_status if %w[in_progress blocked].include?(manual_status)
      return "done" if commit_links.any?

      "todo"
    end
  end
end
