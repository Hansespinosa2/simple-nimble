require "test_helper"

# S-09:AC-3
class SpecSyncCoverageTest < ActiveSupport::TestCase
  test "counts only explicit comment tags and ignores fixture strings" do
    source = <<~RUBY
      # S-05:AC-1 S-05:AC-1
      message = "S-06:AC-2"
      # A prose mention of S-07:AC-1 is not a tag.
    RUBY

    assert_equal [ "S-05:AC-1" ], SpecSync::TestCoverage.references_in(source)
  end
end
