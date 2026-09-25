require "test_helper"
require "stringio"

# S-01:AC-7 S-01:AC-8 S-10:AC-1 S-10:AC-2 S-10:AC-8
class CharacterImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed unless CharacterClass.exists?(name: "Berserker")
    @account = Account.create!(display_name: "Import Player", email: "import-player-#{SecureRandom.hex(4)}@example.com")
  end

  test "the import page explains constraints and offers both templates" do
    get new_character_import_url

    assert_response :success
    assert_select "h1", "Import a character"
    assert_select "form[action='#{character_imports_path}'][enctype='multipart/form-data']"
    assert_select "input[type='file'][accept*='.json']"
    assert_select "a[href='#{character_import_template_path(kind: 'json')}']", text: "Download JSON template"
    assert_select "a[href='#{character_import_template_path(kind: 'csv')}']", text: "Download CSV template"
    assert_includes response.body, "every finalized level-up in order"
    assert_includes response.body, "save a draft"
  end

  test "the downloadable templates carry the supported contract and CSV headings" do
    get character_import_template_url(kind: "json")

    assert_response :success
    assert_match(/attachment/, response.headers.fetch("Content-Disposition"))
    json = JSON.parse(response.body)
    assert_equal CharacterImportService::FORMAT_NAME, json.fetch("format")
    assert_equal CharacterImportService::FORMAT_VERSION, json.fetch("format_version")

    get character_import_template_url(kind: "csv")

    assert_response :success
    assert_equal CharacterImportService::CSV_HEADERS, CSV.parse(response.body, headers: true).headers
  end

  test "a successful multipart upload is attached to the signed-in player and redirects to its draft" do
    source_character = create_valid_character
    payload = source_character.snapshot_payload.merge(
      "format" => CharacterImportService::FORMAT_NAME,
      "format_version" => CharacterImportService::FORMAT_VERSION,
      "character" => source_character.snapshot_payload.fetch("character").merge("id" => source_character.id),
      "creation" => source_character.import_creation_snapshot,
      "level_ups" => source_character.interchange_level_ups
    )

    post sessions_url, params: { account: { display_name: @account.display_name, email: @account.email, role: @account.role } }
    Tempfile.create([ "simple-nimble-import", ".json" ]) do |file|
      file.write(JSON.generate(payload))
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: "hero.json")

      assert_difference "Character.count", 1 do
        post character_imports_url, params: { file: upload }
      end
    end

    imported = Character.order(:id).last
    assert_redirected_to character_url(imported)
    assert imported.draft?
    assert_equal @account, imported.account
    assert_equal "imported", imported.character_revisions.order(:id).last.event_type
  end

  test "a malformed multipart upload rerenders actionable errors without creating a character" do
    Tempfile.create([ "simple-nimble-import", ".json" ]) do |file|
      file.write("{")
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: "broken.json")

      assert_no_difference "Character.count" do
        post character_imports_url, params: { file: upload }
      end
    end

    assert_response :unprocessable_entity
    assert_select "[role='alert']", /JSON file is malformed/
  end

  private
    def create_valid_character
      klass = CharacterClass.find_by!(name: "Berserker")
      character = Character.new(
        name: "External Hero",
        character_class: klass,
        ancestry: Ancestry.find_by!(name: "Human"),
        background: Background.find_by!(name: "Fearless"),
        ruleset_version: RulesetVersion.find_by!(name: "Nimble", version: "v2.0.1"),
        level: 1,
        stat_array: "balanced"
      )
      character.valid?
      character.skill_set.might += 4
      stats = character.stat_set.attributes.slice(*Character::STAT_NAMES).transform_values(&:to_i)
      language_count = character.language_choice_count(stats)
      character.language_choices = character.language_choice_options_for(stats, excluding: []).first(language_count)
      character.save!
      character.finalize_creation!
      character
    end
end
