require "test_helper"

class SpellsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get spells_url
    assert_response :success
  end

  test "should get show" do
    spell = spells(:one)
    get spell_url(spell)
    assert_response :success
  end
end
