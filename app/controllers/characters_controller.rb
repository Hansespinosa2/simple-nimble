class CharactersController < ApplicationController
  before_action :set_character, only: %i[ show edit update destroy finalize tracker history ]
  before_action :require_character_owner, only: %i[ edit update destroy finalize tracker history ]
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
    @character = Character.new(level: 1, status: "draft", ruleset_version: current_ruleset)
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
      :conditions, :inventory, :game_notes,
      { trait_set_attributes: [ :id, :current_actions, :current_hit_dice, :current_hp, :current_wounds, :current_mana, :current_resource, :temp_hp ] }
    ])

    if @character.update(tracker_attributes)
      @character.record_revision!(event_type: "game_update", summary: "In-game state updated", from_level: @character.level, to_level: @character.level)
      redirect_to @character, notice: "Game state saved."
    else
      redirect_to @character, alert: "Game state could not be saved."
    end
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
        :conditions,
        :inventory,
        :game_notes,
        :character_class_id,
        :ancestry_id,
        :background_id,
        :stat_array,
        {
          skill_set_attributes: skill_set_params_list
        },
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

    def creation_error_payload
      {
        errors: @character.errors.full_messages,
        explanations: @character.creation_explanations
      }
    end

    def builder_rules
      {
        stat_arrays: Character::STAT_ARRAYS,
        classes: @character_classes.index_by(&:id).transform_values do |character_class|
          {
            key_stats: character_class.key_stats,
            secondary_stats: character_class.secondary_stats,
            hit_die: character_class.hit_die,
            starting_hp: character_class.starting_hp,
            spell_schools: character_class.spell_schools,
            source_reference: character_class.source_reference,
            starting_gear: character_class.starting_gear,
            armor_proficiencies: character_class.armor_proficiencies,
            weapon_proficiencies: character_class.weapon_proficiencies,
            resource: character_class.resource_rules
          }
        end,
        ancestries: @ancestries.index_by(&:id).transform_values do |ancestry|
          {
            summary: ancestry.trait_summary,
            speed_modifier: ancestry.speed_modifier,
            initiative_modifier: ancestry.initiative_modifier,
            all_skills_bonus: ancestry.all_skills_bonus,
            armor_modifier: ancestry.armor_modifier,
            max_wounds_modifier: ancestry.max_wounds_modifier
          }
        end,
        backgrounds: @backgrounds.index_by(&:id).transform_values do |background|
          {
            description: background.description,
            prerequisite_stat: background.prerequisite_stat,
            prerequisite_max: background.prerequisite_max
          }
        end
      }
    end
end
