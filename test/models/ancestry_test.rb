require "test_helper"

class AncestryTest < ActiveSupport::TestCase
  # S-02:AC-1 S-05:AC-2 S-05:AC-6
  test "stores structured ancestry modifiers with safe defaults" do
    ancestry = Ancestry.create!(name: "Test Halfling", size: "Small")

    assert_equal 0, ancestry.speed_modifier
    assert_equal 0, ancestry.initiative_modifier
    assert_equal 0, ancestry.all_skills_bonus
    assert_equal 0, ancestry.max_hit_dice_modifier
    assert_equal 0, ancestry.max_wounds_modifier
    assert_equal 0, ancestry.armor_modifier
    assert_equal({}, ancestry.skill_modifiers.to_h)
    assert_equal [], ancestry.language_names
  end

  test "requires a unique name and size" do
    assert_not Ancestry.new(name: "", size: "Small").valid?
    assert_not Ancestry.new(name: "Fresh", size: "").valid?
    assert_not Ancestry.new(name: ancestries(:one).name, size: "Medium").valid?
  end
end
