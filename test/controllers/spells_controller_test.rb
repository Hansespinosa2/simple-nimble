require "test_helper"

class SpellsControllerTest < ActionDispatch::IntegrationTest
  # S-02:AC-1 S-05:AC-6 S-09:AC-3
  test "should get index" do
    get spells_url
    assert_response :success
    assert_select "h1", "Spells#index"
    assert_includes response.body, spells(:one).name
  end

  test "should get show" do
    spell = spells(:one)
    get spell_url(spell)
    assert_response :success
    assert_select "h1", "Spells#show"
    assert_includes response.body, spell.description
    assert_includes response.body, "Action Cost"
  end
end
