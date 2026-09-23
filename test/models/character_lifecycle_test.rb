require "test_helper"

# S-01:AC-1 S-01:AC-3 S-01:AC-4 S-01:AC-6 S-02:AC-1 S-02:AC-2 S-02:AC-3 S-03:AC-2 S-03:AC-3 S-04:AC-1 S-04:AC-2 S-05:AC-1 S-05:AC-2 S-05:AC-3 S-05:AC-4 S-05:AC-5 S-07:AC-1 S-07:AC-2 S-07:AC-3 S-07:AC-5
class CharacterLifecycleTest < ActiveSupport::TestCase
  setup do
    @ruleset = RulesetVersion.find_or_create_by!(name: "Nimble", version: "v2.0.1") do |ruleset|
      ruleset.source_reference = "Chapter 3, Character Creation"
    end
    @character_class = CharacterClass.create!(
      name: "Lifecycle Warrior",
      key_stat_one: "strength",
      key_stat_two: "dexterity",
      hit_die: "1d10",
      starting_hp: 16,
      save_bonus_stat: "strength",
      save_penalty_stat: "intelligence"
    )
    @ancestry = Ancestry.create!(name: "Lifecycle Human", size: "Medium", all_skills_bonus: 1, initiative_modifier: 1)
    @background = Background.create!(name: "Lifecycle Background", description: "No prerequisite")
  end

  test "new characters are drafts with rules-derived values and an initial revision" do
    character = Character.create!(
      name: "Aster",
      level: 1,
      character_class: @character_class,
      ancestry: @ancestry,
      background: @background,
      stat_array: "standard",
      ruleset_version: @ruleset,
      skill_set_attributes: { might: 7 }
    )

    assert character.draft?
    assert character.legal_for_creation?
    assert_equal 2, character.stat_set.strength
    assert_equal 2, character.stat_set.dexterity
    assert_equal 7, character.skill_set.might
    assert_equal 4, character.skill_points_spent
    assert_equal 2, character.trait_set.armor
    assert_equal "Common", character.languages.split(", ").first
    assert_equal "created", character.character_revisions.order(:id).last.event_type
  end

  test "invalid drafts can be saved but cannot be finalized" do
    character = Character.create!(name: "Incomplete", level: 1)

    assert character.draft?
    assert_not character.legal_for_creation?
    assert_includes character.creation_issues.map { |issue| issue[:message] }, "Choose a class before finalizing."
    assert_raises(ActiveRecord::RecordInvalid) { character.finalize_creation! }
  end

  test "creation requires all four starting skill points" do
    character = Character.create!(
      name: "Underfunded",
      level: 1,
      character_class: @character_class,
      ancestry: @ancestry,
      background: @background,
      stat_array: "standard",
      ruleset_version: @ruleset
    )

    assert_not character.legal_for_creation?
    assert_includes character.creation_issues.map { |issue| issue[:message] }, "Spend 4 more skill points before finalizing."
    assert_raises(ActiveRecord::RecordInvalid) { character.finalize_creation! }
  end

  test "finalizing creates a playable snapshot" do
    character = Character.create!(
      name: "Ready",
      level: 1,
      character_class: @character_class,
      ancestry: @ancestry,
      background: @background,
      stat_array: "balanced",
      ruleset_version: @ruleset,
      skill_set_attributes: { might: 7 }
    )

    assert_difference -> { character.character_revisions.count }, 1 do
      character.finalize_creation!
    end

    assert character.reload.playable?
    revision = character.character_revisions.order(:id).last
    assert_equal "finalized", revision.event_type
    assert_equal "Ready", revision.snapshot.fetch("character").fetch("name")
  end

  test "creation explanations cite a gated background prerequisite" do
    gated_background = Background.create!(
      name: "Only Smart Enough",
      description: "A test gate",
      prerequisite_stat: "intelligence",
      prerequisite_max: -1
    )
    character = Character.new(
      name: "Too Clever",
      level: 1,
      character_class: @character_class,
      ancestry: @ancestry,
      background: gated_background,
      stat_array: "standard",
      ruleset_version: @ruleset
    )
    character.valid?

    issue = character.creation_explanations.find { |explanation| explanation[:message].include?("requires") }
    assert_equal "blocked", issue[:type]
    assert_equal "Chapter 2, Backgrounds", issue[:source_ref]
    assert_equal "Nimble v2.0.1", issue[:context]
  end

  test "every creation explanation carries its source and active rules context" do
    character = Character.new(name: "Unfinished", level: 1)

    explanations = character.creation_explanations
    assert_operator explanations.length, :>=, 1

    explanations.each do |explanation|
      assert_equal "blocked", explanation[:type]
      assert explanation[:source_ref].present?
      assert explanation[:quote].present?
      assert_equal character.rules_context_label, explanation[:context]
    end
  end

  test "creation preserves a legal distribution of the four extra skill points" do
    character = Character.create!(
      name: "Specialist",
      level: 1,
      character_class: @character_class,
      ancestry: @ancestry,
      background: @background,
      stat_array: "standard",
      ruleset_version: @ruleset,
      skill_set_attributes: { might: 7 }
    )

    assert_equal 7, character.skill_set.might
    assert_equal 4, character.skill_points_spent
    assert character.legal_for_creation?
  end
end
