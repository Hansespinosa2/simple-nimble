require "test_helper"

class SpecSyncCatalogTest < ActiveSupport::TestCase
  test "parses numbered specs and acceptance criteria" do
    catalog = SpecSync::Catalog.new

    spec = catalog.specs.find { |entry| entry.id == "S-05" }

    assert_not_nil spec
    assert_equal "Character Creation", spec.title
    assert_equal "specs/app/05-character-creation.md", spec.path

    criterion = spec.acceptance_criteria.find { |entry| entry.reference.to_s == "S-05:AC-1" }

    assert_not_nil criterion
    assert_equal "Behavioral", criterion.type
    assert_match(/prevents finalization until they are valid/i, criterion.criterion)
    assert_equal "[Assumed: verify]", criterion.spec_confidence
  end
end
