require "test_helper"

class SpecSyncTrackerTest < ActiveSupport::TestCase
  FakeCatalog = Struct.new(:specs, :references)
  FakeStore = Struct.new(:manual_statuses) do
    def manual_status(reference)
      manual_statuses[reference.to_s]
    end

    def validate!(valid_references:)
      invalid = manual_statuses.keys - valid_references.to_a
      raise "Invalid references: #{invalid.join(', ')}" if invalid.any?
    end
  end

  FakeGitCommitIndex = Struct.new(:links_by_reference)

  test "resolves done from git links and active work from manual status" do
    reference = SpecSync::Reference.parse("S-06:AC-2")
    criterion = SpecSync::AcceptanceCriterion.new(
      reference:,
      type: "Behavioral",
      criterion: "Allows only legal choices",
      spec_confidence: "[Validated]"
    )
    spec = SpecSync::SpecDocument.new(
      id: "S-06",
      title: "Level-Up",
      status: "Draft",
      path: "specs/app/06-level-up.md",
      acceptance_criteria: [ criterion ]
    )

    tracker = SpecSync::Tracker.new(
      catalog: FakeCatalog.new([ spec ], [ reference ]),
      status_store: FakeStore.new({ "S-06:AC-2" => "blocked" }),
      git_commit_index: FakeGitCommitIndex.new({
        "S-06:AC-2" => [ SpecSync::CommitLink.new(sha: "abcdef1", summary: "feat: cover S-06:AC-2") ]
      })
    )

    status = tracker.criterion_statuses.first

    assert_equal "blocked", status.implementation_status
    assert_equal "blocked", status.manual_status
    assert_equal 1, status.commit_links.length
  end

  test "filters by spec id or exact criterion reference" do
    first_reference = SpecSync::Reference.parse("S-05:AC-1")
    second_reference = SpecSync::Reference.parse("S-06:AC-1")
    specs = [
      SpecSync::SpecDocument.new(
        id: "S-05",
        title: "Character Creation",
        status: "Draft",
        path: "specs/app/05-character-creation.md",
        acceptance_criteria: [
          SpecSync::AcceptanceCriterion.new(
            reference: first_reference,
            type: "Behavioral",
            criterion: "Criterion one",
            spec_confidence: "[Validated]"
          )
        ]
      ),
      SpecSync::SpecDocument.new(
        id: "S-06",
        title: "Level-Up",
        status: "Draft",
        path: "specs/app/06-level-up.md",
        acceptance_criteria: [
          SpecSync::AcceptanceCriterion.new(
            reference: second_reference,
            type: "Behavioral",
            criterion: "Criterion two",
            spec_confidence: "[Validated]"
          )
        ]
      )
    ]

    tracker = SpecSync::Tracker.new(
      catalog: FakeCatalog.new(specs, [ first_reference, second_reference ]),
      status_store: FakeStore.new({}),
      git_commit_index: FakeGitCommitIndex.new({})
    )

    assert_equal [ "S-05:AC-1" ], tracker.criterion_statuses(filter: "S-05").map { |row| row.reference.to_s }
    assert_equal [ "S-06:AC-1" ], tracker.criterion_statuses(filter: "S-06:AC-1").map { |row| row.reference.to_s }
  end
end
