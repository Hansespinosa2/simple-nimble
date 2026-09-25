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

  test "stores flat bonuses and language grants separately from prose" do
    background = Background.create!(
      name: "Structured Origin",
      description: "A source-backed origin.",
      initiative_modifier: 1,
      armor_modifier: -1,
      skill_modifiers: { naturecraft: 1 },
      language_grants: [ "Goblin" ]
    )

    assert_equal 1, background.initiative_modifier
    assert_equal(-1, background.armor_modifier)
    assert_equal 1, background.skill_bonus_for("naturecraft")
    assert_equal [ "Goblin" ], background.language_names
  end

  # S-02:AC-1 S-02:AC-2 S-05:AC-2 S-09:AC-3
  test "source-backed background guidance covers the complete seeded catalog" do
    Rails.application.load_seed
    feature_notes = Rules::NimbleCatalog.background_feature_notes
    choice_rules = Rules::NimbleCatalog.background_spell_choices
    covered_backgrounds = (feature_notes.keys + choice_rules.keys).uniq.sort

    assert_equal 24, covered_backgrounds.length
    assert_empty covered_backgrounds - Background.pluck(:name)
    feature_notes.each do |name, note|
      assert_predicate note.fetch("manual_effect"), :present?, "#{name} must explain its non-automated rule effect"
      assert_match(/\ACore Rules 2\.0\.1, p\. 2[89]\z/, note.fetch("source_ref"), "#{name} must cite its source page")
    end
  end
end
