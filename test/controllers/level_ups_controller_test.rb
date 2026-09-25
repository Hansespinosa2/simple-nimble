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
    assert_select ".preview-list", /Hit Dice\s*2 \/ 2/
    assert_select ".explanation-stack", /Max Hit Dice increases by 1 to 2/
    assert_select ".explanation-stack", /Core Rules 2\.0\.1, p\. 21.*More Endurance\. Your Hit Die max increases by 1/
    assert_select ".skill-rule-note", /explicitly grant.*Songweaver's Jack of All Trades.*Safe Rest.*Core Rules 2\.0\.1, p\. 21/
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
    assert_select ".field-hint", /Choose a subclass at level #{@character.character_class.subclass_choice_level}/
  end

  # S-02:AC-2 S-06:AC-2 S-07:AC-2 S-09:AC-3
  test "level-twenty form explains that capstone stat gains may exceed the typical maximum" do
    level_eighteen_berserker!
    post character_level_ups_url(@character), params: {
      level_up: {
        from_level: 18,
        to_level: 19,
        skill_name: "might",
        feature_choices: { "Epic Boon" => [ "Epic Speed" ] }
      },
      finalize: "1"
    }

    assert_redirected_to character_url(@character)
    get new_character_level_up_url(@character)

    assert_response :success
    assert_select ".field-hint", /The Core Rules describe \+5 as typical; this level-20 capstone may raise stats above it \(Core Rules 2\.0\.1, p\. 6\)/
  end

  # S-02:AC-2 S-02:AC-4 S-06:AC-2
  test "level-three page separates story-based subclasses and explains the GM rule" do
    commander = Character.create!(
      name: "Commander Story Choice Hero",
      character_class: CharacterClass.find_by!(name: "Commander"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Draconic", "Primordial" ],
      ruleset_version: RulesetVersion.active.first
    )
    creation_skill = Character::SKILL_TO_STAT.find { |_skill, stat| commander.character_class.key_stats.include?(stat) }.first
    commander.skill_set.update!(creation_skill => commander.skill_initial_value(creation_skill) + 4)
    commander.finalize_creation!
    commander.update_columns(level: 2, status: "playable")
    commander.skill_set.update!(creation_skill => commander.skill_value(creation_skill) + 1)
    assert commander.reload.level_up_eligible?, commander.creation_issues.map { |issue| issue[:message] }.join(" | ")

    get new_character_level_up_url(commander)

    assert_response :success
    assert_select "select[name='level_up[subclass_name]'] option", text: "Champion of the Bulwark"
    assert_select "select[name='level_up[subclass_name]'] option", text: "Spellblade", count: 0
    assert_select ".field-hint", /Story-based options: Spellblade/
    assert_select ".field-hint", /At your GM's discretion.*replacing your existing subclass/
    assert_select ".field-hint", /Heroes 2.0.1, p. 73/
  end

  test "level-four page exposes the source-backed feature choice" do
    @character.update_columns(level: 3, status: "playable", subclass_name: "Path of the Mountainheart")
    @character.skill_set.update!(might: 9)

    get new_character_level_up_url(@character)

    assert_response :success
    assert_select "select[name='level_up[feature_choices][Savage Arsenal][]']"
    assert_select "select[name='level_up[feature_choices][Savage Arsenal][]'] option:first-child[value='']", text: "Choose an option"
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

  # S-02:AC-1 S-02:AC-2 S-06:AC-2 S-06:AC-3 S-06:AC-4 S-09:AC-1 S-09:AC-3
  test "level-nineteen finalization requires and records a source-defined Epic Boon" do
    level_eighteen_berserker!
    starting_speed = @character.trait_set.speed
    starting_initiative = @character.trait_set.initiative

    get new_character_level_up_url(@character)

    assert_response :success
    assert_select "select[name='level_up[feature_choices][Epic Boon][]'] option[value='Epic Speed']", text: /Epic Speed.*\+4 Speed and \+4 Initiative/
    assert_select ".feature-choice-field", /Gamemaster's Guide 2\.0, p\. 23/
    assert_select ".feature-choice-field", /Level 19 Epic Boon\. Choose an Epic Boon/

    post character_level_ups_url(@character), params: {
      level_up: { from_level: 18, to_level: 19, skill_name: "might" },
      finalize: "1"
    }

    assert_response :unprocessable_entity
    assert_select ".blocked-choice-list .blocked-choice strong", text: "Choose 1 Epic Boon option at level 19."
    assert_select ".blocked-choice-list .blocked-choice small", /Gamemaster's Guide 2\.0, p\. 23/
    assert_select ".blocked-choice-list .blocked-choice small", /Choose an Epic Boon \(see pg\. 23/
    assert_equal 18, @character.reload.level
    assert LevelUp.last.draft?

    post character_level_ups_url(@character), params: {
      level_up: {
        from_level: 18,
        to_level: 19,
        skill_name: "might",
        feature_choices: { "Epic Boon" => [ "Epic Speed" ] }
      },
      finalize: "1"
    }

    assert_redirected_to character_url(@character)
    assert_equal 19, @character.reload.level
    assert_equal [ "Epic Speed" ], @character.recorded_feature_choices.fetch("Epic Boon")
    assert_equal starting_speed + 4, @character.trait_set.speed
    assert_equal starting_initiative + 4, @character.trait_set.initiative

    get character_url(@character)
    assert_select ".progression-entry-choice", /Epic Speed/
    assert_select ".progression-entry-choice", /\+4 Speed and \+4 Initiative/
    assert_select ".progression-entry-choice", /Gamemaster's Guide 2\.0, p\. 23/
  end

  # S-02:AC-1 S-02:AC-2 S-06:AC-2 S-06:AC-3 S-06:AC-4 S-09:AC-1 S-09:AC-3
  test "Epic Stats requires three different stat picks and applies them on level-up" do
    level_eighteen_berserker!
    starting_stats = @character.stat_set.attributes.slice("strength", "dexterity", "intelligence", "will").transform_values(&:to_i)
    starting_skills = @character.skill_set.attributes.slice(*Character::SKILL_NAMES).transform_values(&:to_i)

    post character_level_ups_url(@character), params: {
      level_up: {
        from_level: 18,
        to_level: 19,
        skill_name: "might",
        feature_choices: { "Epic Boon" => [ "Epic Stats" ] }
      },
      finalize: "1"
    }

    assert_response :unprocessable_entity
    assert_select ".blocked-choice-list .blocked-choice strong", text: "Choose 3 Epic Stats · stat increases options at level 19."
    assert_select ".feature-choice-field", /Epic Stats · stat increases/
    assert_select ".feature-choice-field option[value='strength']", text: "Strength"

    post character_level_ups_url(@character), params: {
      level_up: {
        from_level: 18,
        to_level: 19,
        skill_name: "might",
        feature_choices: {
          "Epic Boon" => [ "Epic Stats" ],
          "Epic Stats · stat increases" => %w[strength dexterity will]
        }
      },
      finalize: "1"
    }

    assert_redirected_to character_url(@character)
    @character.reload
    assert_equal starting_stats.fetch("strength") + 1, @character.stat_set.strength
    assert_equal starting_stats.fetch("dexterity") + 1, @character.stat_set.dexterity
    assert_equal starting_stats.fetch("will") + 1, @character.stat_set.will
    assert_equal starting_stats.fetch("intelligence"), @character.stat_set.intelligence
    assert_equal %w[strength dexterity will], @character.feature_choice_ledger.fetch("Epic Stats · stat increases").fetch("19")
    Character::SKILL_NAMES.each do |skill|
      expected_increase = %w[strength dexterity will].include?(Character::SKILL_TO_STAT.fetch(skill)) ? 1 : 0
      expected_increase += 1 if skill == "might"
      assert_equal starting_skills.fetch(skill) + expected_increase, @character.skill_set.public_send(skill), "#{skill} reflects the source-defined stat and skill increases"
    end
  end

  test "level-three Mage page exposes the utility-school choice" do
    Rails.application.load_seed
    mage = Character.create!(
      name: "Utility Choice Controller Hero",
      level: 1,
      character_class: CharacterClass.find_by!(name: "Mage"),
      ancestry: Ancestry.find_by!(name: "Human"),
      background: Background.find_by!(name: "Fearless"),
      stat_array: "standard",
      language_choices: [ "Draconic", "Primordial" ],
      skill_set_attributes: { arcana: 7 }
    )
    mage.finalize_creation!
    mage.update_columns(level: 2, status: "playable")
    mage.skill_set.update!(arcana: 8)

    get new_character_level_up_url(mage)

    assert_response :success
    assert_select "select[name='level_up[spell_choices][Elemental Mastery][]']"
    assert_select "select[name='level_up[spell_choices][Elemental Mastery][]'] option:first-child[value='']", text: "Choose an option"
    assert_select ".spell-choice-field", /Heroes 2.0.1, p. 33/
    assert_select ".spell-choice-field option", text: "Fire"
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

  test "a blocked required choice retains its source and source note in the form" do
    level_up = @character.level_ups.create!(from_level: 1, to_level: 2, skill_name: "might")

    patch character_level_up_url(@character, level_up), params: {
      level_up: { skill_name: "" },
      finalize: "1"
    }

    assert_response :unprocessable_entity
    assert_select ".blocked-choice-list .blocked-choice strong", text: "Choose one skill to improve."
    assert_select ".blocked-choice-list .blocked-choice small", /Heroes 2.0.1, p. 56/
    assert_select ".blocked-choice-list .blocked-choice small", /More Skilled\. Gain 1 skill point/
    assert_select ".blocked-choice-list .blocked-choice .source-note", /explicitly grant 1 skill point.*Songweaver's Jack of All Trades.*Safe Rest/
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

  private
    def level_eighteen_berserker!
      @character.update_columns(level: 18, status: "playable", subclass_name: "Path of the Red Mist")
      remaining_points = @character.skill_point_budget - @character.skill_points_spent
      maximum_skill = Rules::NimbleCatalog.derived_values.fetch("max_skill").to_i
      skill_updates = {}

      Character::SKILL_NAMES.each do |skill|
        current_value = @character.skill_value(skill).to_i
        increase = [ remaining_points, maximum_skill - current_value ].min
        next unless increase.positive?

        skill_updates[skill] = current_value + increase
        remaining_points -= increase
        break if remaining_points.zero?
      end

      @character.skill_set.update!(skill_updates)
      assert_equal 0, remaining_points, "fixture has enough legal skill capacity to represent level 18"
      assert @character.reload.level_up_eligible?, @character.reload.creation_issues.map { |issue| issue.fetch(:message) }.join(" | ")
    end
end
