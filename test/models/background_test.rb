require "test_helper"

class BackgroundTest < ActiveSupport::TestCase
  # S-02:AC-1 S-05:AC-3 S-05:AC-6 S-07:AC-1
  test "a background without a prerequisite is available to any stat set" do
    background = Background.create!(name: "Open Road", description: "No gate")

    assert background.satisfied_by?(nil)
    assert background.satisfied_by?(StatSet.new(strength: -2, dexterity: 0, intelligence: 3, will: 1))
  end

  test "checks a structured prerequisite against the governing stat" do
    background = Background.create!(
      name: "Quiet Scholar",
      description: "Requires a low Strength.",
      prerequisite_stat: "strength",
      prerequisite_max: 0
    )
    low_strength = StatSet.new(strength: 0, dexterity: 1, intelligence: 2, will: 0)
    strong = StatSet.new(strength: 1, dexterity: 1, intelligence: 2, will: 0)

    assert background.satisfied_by?(low_strength)
    assert_not background.satisfied_by?(strong)
  end

  test "does not accept a prerequisite without a threshold" do
    background = Background.new(name: "Broken Gate", prerequisite_stat: "will")

    assert_not background.valid?
    assert_includes background.errors[:prerequisite_max], "can't be blank"
  end
end
