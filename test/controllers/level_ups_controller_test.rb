require "test_helper"

# S-01:AC-2 S-01:AC-3 S-06:AC-1 S-06:AC-2 S-06:AC-4 S-06:AC-5 S-07:AC-4 S-09:AC-1 S-09:AC-3
class LevelUpsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed unless CharacterClass.where(name: "Berserker").exists?
    @character = Character.find_or_initialize_by(name: "Controller Hero")
    @character.assign_attributes(
      level: 1,
      character_class: CharacterClass.find_by!(name: "Berserker"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      ruleset_version: RulesetVersion.active.first,
      skill_set_attributes: { might: 7 }
    )
    @character.save!
    @character.finalize_creation! if @character.draft?
  end

  test "level-up page is available only for a playable character" do
    get new_character_level_up_url(@character)

    assert_response :success
    assert_select "h1", /Level up to 2/
    assert_select "select[name='level_up[skill_name]']"
    assert_select ".progression-preview", /Intensifying Fury/
    assert_select ".progression-preview .source-note", /Heroes 2.0.1/
  end

  test "level-three page exposes the class subclass choice" do
    @character.update_columns(level: 2, status: "playable")
    @character.skill_set.update!(might: 8)

    assert @character.reload.level_up_eligible?, @character.reload.creation_issues.map { |issue| issue[:message] }.join(" | ")

    get new_character_level_up_url(@character)

    assert_response :success
    assert_select "select[name='level_up[subclass_name]']"
    assert_select "select[name='level_up[subclass_name]'] option", text: "Path of the Mountainheart"
  end

  test "level-four page exposes the source-backed feature choice" do
    @character.update_columns(level: 3, status: "playable", subclass_name: "Path of the Mountainheart")
    @character.skill_set.update!(might: 9)

    get new_character_level_up_url(@character)

    assert_response :success
    assert_select "select[name='level_up[feature_choices][Savage Arsenal][]']"
    assert_select ".feature-choice-field", /Heroes 2.0.1, p. 10/
    assert_select ".feature-choice-field option", text: "Death Blow"
  end

  test "applying a feature choice from the form persists it" do
    @character.update_columns(level: 3, status: "playable", subclass_name: "Path of the Mountainheart")
    @character.skill_set.update!(might: 9)

    post character_level_ups_url(@character), params: {
      level_up: {
        from_level: 3,
        to_level: 4,
        skill_name: "might",
        stat_name: "strength",
        feature_choices: { "Savage Arsenal" => [ "Death Blow" ] }
      },
      finalize: "1"
    }

    assert_redirected_to character_url(@character)
    assert_equal [ "Death Blow" ], @character.reload.recorded_feature_choices.fetch("Savage Arsenal")
  end

  test "saving a draft enters the explicit level-up state without changing the sheet" do
    assert_difference("LevelUp.count") do
      post character_level_ups_url(@character), params: {
        level_up: { from_level: 1, to_level: 2, skill_name: "might", notes: "A new scar." }
      }
    end

    assert_redirected_to character_level_up_url(@character, LevelUp.last)
    assert_equal "level_up", @character.reload.status
    assert_equal 1, @character.level
    draft = LevelUp.last
    assert_equal "might", draft.skill_name
    assert_equal "A new scar.", draft.notes
    assert_equal 2, draft.preview.fetch("level")
  end

  test "applying a legal level-up persists the transition" do
    assert_difference("CharacterRevision.where(event_type: 'level_up').count", 1) do
      post character_level_ups_url(@character), params: {
        level_up: { from_level: 1, to_level: 2, skill_name: "might" },
        finalize: "1"
      }
    end

    assert_redirected_to character_url(@character)
    assert_equal 2, @character.reload.level
    assert @character.playable?
    assert_equal "finalized", LevelUp.last.status
  end

  test "an invalid level-up remains unfinalized and explains the block" do
    level_up = @character.level_ups.create!(from_level: 1, to_level: 2, skill_name: "arcana")

    patch character_level_up_url(@character, level_up), params: {
      level_up: { skill_name: "not_a_skill" },
      finalize: "1"
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "not a recognized skill"
    assert_equal 1, @character.reload.level
    assert level_up.reload.draft?
  end

  test "a stale level-up draft is blocked before it can change the sheet" do
    level_up = @character.level_ups.create!(from_level: 99, to_level: 2, skill_name: "might")

    patch character_level_up_url(@character, level_up), params: {
      level_up: { from_level: 99, to_level: 2, skill_name: "might" },
      finalize: "1"
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "current level"
    assert_equal 1, @character.reload.level
    assert level_up.reload.draft?
  end
end
