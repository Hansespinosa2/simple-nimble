require "test_helper"

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
      ruleset_version: RulesetVersion.active.first
    )
    @character.save!
    @character.finalize_creation! if @character.draft?
  end

  test "level-up page is available only for a playable character" do
    get new_character_level_up_url(@character)

    assert_response :success
    assert_select "h1", /Level up to 2/
    assert_select "select[name='level_up[skill_name]']"
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
    assert_includes response.body, "already at the +12 skill maximum"
    assert_equal 1, @character.reload.level
    assert level_up.reload.draft?
  end
end
