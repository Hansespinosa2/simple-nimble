require "test_helper"

# S-02:AC-2 S-08:AC-4 S-09:AC-3
class ApplicationHelperTest < ActiveSupport::TestCase
  include ApplicationHelper

  test "companion size requirements reflect grouped catalog levels" do
    rule = {
      "minimum_level_by_size" => {
        "Small" => 1,
        "Medium" => 3,
        "Large" => 3,
        "Huge" => 5
      }
    }

    assert_equal [
      "Medium and Large companions require level 3.",
      "Huge companion requires level 5."
    ], companion_size_level_requirements(rule)
  end
end
