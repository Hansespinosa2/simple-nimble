class CharactersController < ApplicationController
  before_action :set_character, only: %i[ show edit update destroy finalize tracker begin_encounter game_feature end_encounter safe_rest field_rest history ]
  before_action :require_character_owner, only: %i[ edit update destroy finalize tracker begin_encounter game_feature end_encounter safe_rest field_rest history ]
  before_action :set_rules_canon_options, only: %i[ index show new edit create update finalize ]

  # GET /characters or /characters.json
  def index
    @characters = visible_characters
    @characters = @characters.where("characters.name LIKE :query", query: "%#{Character.sanitize_sql_like(params[:q].to_s.strip)}%") if params[:q].present?
    @characters = @characters.order(updated_at: :desc)
  end

  # GET /characters/1 or /characters/1.json
  def show
    @revisions = @character.character_revisions.order(created_at: :desc).limit(8)
    @campaigns = current_account&.campaigns&.order(:name) || Campaign.none
  end

  # GET /characters/new
  def new
    @character = Character.new(level: 1, status: "draft", starting_equipment_choice: "class_gear", ruleset_version: current_ruleset)
    @character.ensure_defaults
  end

  # GET /characters/1/edit
  def edit
  end

  # POST /characters or /characters.json
  def create
    @character = Character.new(character_params)
    @character.account = current_account if current_account.present?
    @character.ruleset_version ||= current_ruleset

    respond_to do |format|
      if @character.save
        if finalize_requested?
          if @character.legal_for_creation?
            @character.finalize_creation!
            format.html { redirect_to @character, notice: "Character created and ready to play." }
            format.json { render :show, status: :created, location: @character }
          else
            add_creation_errors
            format.html { render :new, status: :unprocessable_entity }
            format.json { render json: creation_error_payload, status: :unprocessable_entity }
          end
        else
          format.html { redirect_to @character, notice: "Draft saved. Finish the choices when you are ready." }
          format.json { render :show, status: :created, location: @character }
        end
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @character.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /characters/1 or /characters/1.json
  def update
    respond_to do |format|
      if @character.update(character_params)
        @character.record_revision!(event_type: "edited", summary: "Character sheet edited", from_level: @character.level, to_level: @character.level)
        if finalize_requested? && @character.draft?
          if @character.legal_for_creation?
            @character.finalize_creation!
            format.html { redirect_to @character, notice: "Character finalized and ready to play.", status: :see_other }
            format.json { render :show, status: :ok, location: @character }
          else
            add_creation_errors
            format.html { render :edit, status: :unprocessable_entity }
            format.json { render json: creation_error_payload, status: :unprocessable_entity }
          end
        else
          format.html { redirect_to @character, notice: "Character was successfully updated.", status: :see_other }
          format.json { render :show, status: :ok, location: @character }
        end
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @character.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /characters/1 or /characters/1.json
  def destroy
    @character.destroy!

    respond_to do |format|
      format.html { redirect_to characters_path, notice: "Character was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  def finalize
    if @character.draft? && @character.legal_for_creation?
      @character.finalize_creation!
      redirect_to @character, notice: "#{@character.name.presence || 'Character'} is ready to play."
    else
      add_creation_errors
      render :edit, status: :unprocessable_entity
    end
  end

  def tracker
    tracker_attributes = params.expect(character: [
      :conditions, :inventory, :game_notes, :current_gold,
      { trait_set_attributes: [ :id, :current_actions, :current_hit_dice, :current_hp, :current_wounds, :current_mana, :current_resource, :temp_hp, { resource_tracks: [ [ :key, :current ] ] } ] }
    ])
    tracker_event_grants = []
    saved = false
    notice = nil

    @character.with_lock do
      tracker_event_grants = @character.tracker_resource_event_grants_for(
        tracker_attributes.dig(:trait_set_attributes, :resource_tracks)
      )
      wound_events = apply_wound_events!(tracker_attributes)
      normalize_resource_tracks!(tracker_attributes, gained_wounds: wound_events.fetch(:gained_wounds))

      if @character.update(tracker_attributes)
        event_summaries = tracker_event_grants.map do |grant|
          "#{grant.fetch('event_summary')} (#{grant.fetch('source_ref')})"
        end
        summary = ([ "In-game state updated" ] + event_summaries).join("; ")
        notice = ([ "Game state saved." ] + event_summaries).join(" ")
        if wound_events.fetch(:zero_hp_wounds_gained).positive?
          transition_rule = Rules::NimbleCatalog.zero_hp_transition_rules
          if wound_events.fetch(:ignored_wounds).positive?
            summary += "; reached 0 HP while Unyielding Resolve ignored the first Wound (#{transition_rule.fetch('source_ref')})"
          else
            added_wounds = wound_events.fetch(:zero_hp_wounds_gained)
            wound_label = added_wounds == 1 ? "1 Wound" : "#{added_wounds} Wounds"
            summary += "; gained #{added_wounds} Wound#{'s' unless added_wounds == 1} on reaching 0 HP"
            summary += " (#{transition_rule.fetch('source_ref')})"
            notice = "#{notice} The zero-HP rule added #{wound_label}. #{transition_rule.fetch('source_ref')}."
          end
        end
        if wound_events.fetch(:ignored_wounds).positive?
          prevention_rule = @character.wound_prevention_rule
          source_ref = prevention_rule.fetch("source_ref")
          summary += "; Unyielding Resolve ignored the first Wound; Wound-triggered abilities still triggered (#{source_ref})"
          notice = "#{notice} Unyielding Resolve ignored the first Wound; Wound-triggered abilities still triggered. #{source_ref}."
          @character.record_revision!(
            event_type: "unyielding_resolve",
            summary: "Unyielding Resolve ignored the first Wound; Wound-triggered abilities still triggered (#{source_ref})",
            from_level: @character.level,
            to_level: @character.level
          )
        end
        @character.record_revision!(event_type: "game_update", summary:, from_level: @character.level, to_level: @character.level)
        tracker_event_grants.each do |grant|
          event_summary = "#{grant.fetch('event_summary')} (#{grant.fetch('source_ref')})"
          @character.record_revision!(event_type: grant.fetch("event_type"), summary: event_summary, from_level: @character.level, to_level: @character.level)
        end
        saved = true
      end
    end

    if saved
      redirect_to @character, notice: notice
    else
      redirect_to @character, alert: "Game state could not be saved."
    end
  end

  def safe_rest
    @character.take_safe_rest!
    redirect_to @character, notice: "Safe Rest completed. HP, Hit Dice, and tracked resources were refreshed."
  end

  def begin_encounter
    initiative_roll = if params[:initiative_roll].is_a?(ActionController::Parameters)
      params[:initiative_roll].permit(
        { dice_rolls: [], rerolls: [], feature_actions: {
          firebrand_enchant_weapon: [ :used, :target ],
          shadowpath_hunters_mark: [ :used, :target ],
          swiftshift_initiative: [ :used, :choice ]
        } }
      )
    else
      ActionController::Parameters.new
    end
    revision = @character.begin_encounter!(
      dice_rolls: Array(initiative_roll[:dice_rolls]),
      rerolls: Array(initiative_roll[:rerolls]),
      feature_actions: initiative_roll[:feature_actions] || {}
    )
    redirect_to @character, notice: "Initiative recorded. #{revision.summary}."
  rescue ArgumentError => error
    redirect_to @character, alert: error.message
  end

  def game_feature
    attributes = params.expect(game_feature: [ :action, :spell_name, :outcome ])
    case attributes[:action]
    when "summon_bonescythe"
      revision = @character.summon_bonescythe!
      notice = revision.summary
    when "mark_bonescythe_hit"
      revision = @character.mark_bonescythe_hit!(outcome: attributes[:outcome].presence || "hit")
      notice = revision.summary
    when "summon_shadow_minion"
      revision = @character.summon_shadow_minion!
      notice = revision.summary
    when "martyr_spawn"
      revision = @character.martyr_spawn!
      notice = revision.summary
    when "shadow_exploit"
      revision = @character.use_shadow_exploit!(spell_name: attributes[:spell_name])
      notice = revision.summary
    when "my_blood_my_power"
      revision = @character.use_my_blood_my_power!(spell_name: attributes[:spell_name])
      notice = revision.summary
    when "shadowpath_first_attack_advantage"
      revision = @character.use_shadowpath_first_attack_advantage!
      notice = revision.summary
    else
      raise ArgumentError, "Choose a supported game feature."
    end
    redirect_to @character, notice:
  rescue ArgumentError => error
    redirect_to @character, alert: error.message
  end

  def end_encounter
    @character.end_encounter!
    redirect_to @character, notice: "Encounter ended. Encounter-reset counters were refreshed."
  end

  def field_rest
    attributes = params.expect(field_rest: [ :mode, :hit_dice, :die_rolls, :convert_healing_to_mana ])
    result = @character.perform_field_rest!(
      mode: attributes[:mode],
      hit_dice_count: attributes[:hit_dice],
      die_rolls: attributes[:die_rolls].to_s.split(",").map(&:strip).reject(&:blank?),
      convert_healing_to_mana: attributes[:convert_healing_to_mana].to_s == "1"
    )
    rest_name = result.fetch(:mode) == "make_camp" ? "Make Camp" : "Catch Breath"
    notice = "#{rest_name} complete: recovered #{result.fetch(:hp_recovered)} HP."
    if result.fetch(:mana_recovered).positive?
      notice += " Converted #{result.fetch(:hp_healing_forgone)} HP of healing into #{result.fetch(:mana_recovered)} Mana with Epic Mana."
    end
    redirect_to @character, notice:
  rescue ArgumentError => error
    redirect_to @character, alert: error.message
  end

  def history
    @revisions = @character.character_revisions.order(created_at: :desc)
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_character
      @character = Character.find(params.expect(:id))
    end

    def require_character_owner
      return if current_account.blank? && @character.account.blank?
      return if current_account.present? && @character.account == current_account

      redirect_to @character, alert: "Only the player who owns this character can edit it."
    end

    # Populates the rules-canon dropdowns (spec 02/05 creation-flow choices)
    # for the new/edit form and for re-rendering on validation failure.
    def set_rules_canon_options
      @character_classes = CharacterClass.order(:name)
      @ancestries = Ancestry.order(:name)
      @backgrounds = Background.order(:name)
      @stat_arrays = Character::STAT_ARRAYS.keys
      @ruleset_versions = RulesetVersion.active.order(:name, :version)
      @builder_rules = builder_rules
    end

    # Only allow a list of trusted parameters through using expect.
    def character_params
      skill_set_params_list = [ :id, *Character::SKILL_NAMES ]
      params.expect(character: [
        :name,
        :race,
        :nimble_class,
        :level,
        :legacy_background_text,
        :description,
        :languages,
        :spell_school_choice,
        :starting_equipment_choice,
        :conditions,
        :inventory,
        :game_notes,
        :character_class_id,
        :ancestry_id,
        :background_id,
        :stat_array,
        { stat_assignments: Character::STAT_NAMES },
        { language_choices: [] },
        { feature_language_choices: {} },
        {
          skill_set_attributes: skill_set_params_list
        },
        { spell_choices: {} },
        spell_ids: []
      ])
    end

    def visible_characters
      return Character.includes(:character_class, :ancestry, :background, :trait_set) if current_account.blank?

      Character.where(account: [ current_account, nil ]).includes(:character_class, :ancestry, :background, :trait_set)
    end

    def current_ruleset
      RulesetVersion.active.order(:id).first || RulesetVersion.create!(
        name: "Nimble", version: "v2.0.1", source_reference: "Nimble Core Rules, Heroes, and Gamemaster's Guide", published_at: Date.new(2026, 7, 1)
      )
    end

    def finalize_requested?
      params[:finalize].present? || params[:commit].to_s.downcase.include?("ready to play")
    end

    def add_creation_errors
      @character.errors.add(:base, "Resolve the highlighted rules checks before finalizing.") if @character.creation_issues.empty?
      @character.creation_issues.each { |issue| @character.errors.add(:base, issue.fetch(:message)) }
    end

    def apply_wound_events!(tracker_attributes)
      trait_attributes = tracker_attributes[:trait_set_attributes]
      return { gained_wounds: 0, ignored_wounds: 0, zero_hp_wounds_gained: 0 } if trait_attributes.blank?

      current_wounds = @character.trait_set&.current_wounds.to_i
      current_hp = @character.trait_set&.current_hp.to_i
      requested_wounds = trait_attributes[:current_wounds].present? ? trait_attributes[:current_wounds].to_i : current_wounds
      max_wounds = @character.trait_set.max_wounds.to_i
      return { gained_wounds: 0, ignored_wounds: 0, zero_hp_wounds_gained: 0 } if requested_wounds > max_wounds

      zero_hp_transition = trait_attributes[:current_hp].present? && trait_attributes[:current_hp].to_i.zero? && current_hp.positive?
      zero_hp_wounds_gained = 0
      if zero_hp_transition
        rule = Rules::NimbleCatalog.zero_hp_transition_rules
        requested_gain = rule.fetch("wounds_gained").to_i
        zero_hp_wounds_gained = [ [ current_wounds + requested_gain, max_wounds ].min - current_wounds, 0 ].max
        requested_wounds = [ requested_wounds, current_wounds + requested_gain ].max
      end

      requested_wounds = [ requested_wounds, max_wounds ].min
      gained_wounds = [ requested_wounds - current_wounds, 0 ].max
      ignored_wounds = @character.unyielding_resolve_available? && gained_wounds.positive? ? 1 : 0
      trait_attributes[:current_wounds] = requested_wounds - ignored_wounds if trait_attributes[:current_wounds].present? || zero_hp_transition || ignored_wounds.positive?

      { gained_wounds:, ignored_wounds:, zero_hp_wounds_gained: }
    end

    def normalize_resource_tracks!(tracker_attributes, gained_wounds:)
      trait_attributes = tracker_attributes[:trait_set_attributes]
      return if trait_attributes.blank?

      resource_tracks = @character.normalized_resource_tracks(
        trait_attributes[:resource_tracks],
        current_wounds: trait_attributes[:current_wounds],
        current_hp: trait_attributes[:current_hp],
        gained_wounds:
      )
      trait_attributes[:resource_tracks] = resource_tracks
      legacy_values = @character.resource_tracker_values_for(resource_tracks)
      trait_attributes[:current_mana] = legacy_values[:current_mana] unless legacy_values[:current_mana].nil?
      trait_attributes[:current_resource] = legacy_values[:current_resource] unless legacy_values[:current_resource].nil?
    end

    def creation_error_payload
      {
        errors: @character.errors.full_messages,
        explanations: @character.creation_explanations
      }
    end

    def builder_rules
      persisted_character = @character&.persisted?
      character_equipment_state = {
        persisted: persisted_character || false,
        character_class_name: @character&.character_class&.name,
        starting_equipment_choice: @character&.starting_equipment_choice,
        equipped_body_armor_names: persisted_character ? body_armor_names(@character.equipped_armor_profiles) : [],
        other_equipped_body_armor_names: persisted_character ? equipped_nonstarting_body_armor_names : []
      }

      {
        stat_arrays: Character::STAT_ARRAYS,
        derived_values: Rules::NimbleCatalog.derived_values,
        stats: Rules::NimbleCatalog.stats,
        skills: Rules::NimbleCatalog.skills,
        languages: Rules::NimbleCatalog.language_rules,
        starting_equipment: Rules::NimbleCatalog.starting_equipment_rules,
        equipment_armor: Rules::NimbleCatalog.equipment_armor_items,
        character_equipment_state:,
        classes: @character_classes.index_by(&:id).transform_values do |character_class|
          {
            key_stats: character_class.key_stats,
            secondary_stats: character_class.secondary_stats,
            hit_die: character_class.hit_die,
            starting_hp: character_class.starting_hp,
            save_bonus: character_class.save_bonus_stat,
            save_penalty: character_class.save_penalty_stat,
            spell_schools: character_class.spell_schools,
            spell_school_choice: character_class.spell_school_choice_rule,
            source_reference: character_class.source_reference,
            starting_gear: character_class.starting_gear,
            language_grants: Rules::NimbleCatalog.class_language_rules_for(character_class.name),
            armor_proficiencies: character_class.armor_proficiencies,
            weapon_proficiencies: character_class.weapon_proficiencies,
            armor_rules: character_class.armor_rules,
            derived_effects: Rules::NimbleCatalog.class_derived_effects(character_class.name),
            resource: character_class.resource_rules
          }
        end,
        ancestries: @ancestries.index_by(&:id).transform_values do |ancestry|
          {
            summary: ancestry.trait_summary,
            speed_modifier: ancestry.speed_modifier,
            initiative_modifier: ancestry.initiative_modifier,
            all_skills_bonus: ancestry.all_skills_bonus,
            skill_modifiers: ancestry.skill_modifiers,
            armor_modifier: ancestry.armor_modifier,
            max_hit_dice_modifier: ancestry.max_hit_dice_modifier,
            max_wounds_modifier: ancestry.max_wounds_modifier,
            language_grants: ancestry.language_names
          }
        end,
        backgrounds: @backgrounds.index_by(&:id).transform_values do |background|
          spell_choice_rule = Rules::NimbleCatalog.background_spell_choice_for(background.name)
          feature_note = Rules::NimbleCatalog.background_feature_note_for(background.name)
          {
            description: background.description,
            feature_note: feature_note,
            prerequisite_stat: background.prerequisite_stat,
            prerequisite_max: background.prerequisite_max,
            initiative_modifier: background.initiative_modifier,
            armor_modifier: background.armor_modifier,
            max_hit_dice_modifier: background.max_hit_dice_modifier,
            max_wounds_modifier: background.max_wounds_modifier,
            skill_modifiers: background.skill_modifiers,
            language_grants: background.language_names,
            starting_spell_choice: spell_choice_rule.present?,
            starting_spell_choice_rule: spell_choice_rule
          }
        end
      }
    end

    def body_armor_names(profiles)
      profiles.filter_map do |profile|
        profile.fetch("name") if profile.fetch("rules").fetch("kind") == "armor"
      end
    end

    def equipped_nonstarting_body_armor_names
      @character.inventory_items.where(equipped: true, starting_gear: false).filter_map do |item|
        rules = Rules::NimbleCatalog.equipment_armor_item(item.name)
        item.name if rules&.fetch("kind") == "armor"
      end
    end
end
