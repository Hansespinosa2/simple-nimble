class CharactersController < ApplicationController
  before_action :set_character, only: %i[ show edit update destroy ]

  # GET /characters or /characters.json
  def index
    @characters = Character.all
  end

  # GET /characters/1 or /characters/1.json
  def show
  end

  # GET /characters/new
  def new
    @character = Character.new
    @character.ensure_defaults
  end

  # GET /characters/1/edit
  def edit
  end

  # POST /characters or /characters.json
  def create
    @character = Character.new(character_params)

    respond_to do |format|
      if @character.save
        format.html { redirect_to @character, notice: "Character was successfully created." }
        format.json { render :show, status: :created, location: @character }
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
        format.html { redirect_to @character, notice: "Character was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @character }
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

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_character
      @character = Character.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through using expect.
    def character_params
      stats_params_list = [ :id, :name, :value ]
      skills_params_list = [ :id, :name, :value ]
      trait_set_params_list = [ :id, :initiative, :speed, :hit_die, :current_hit_dice, :max_hit_dice, :current_actions, :max_actions, :armor, :temp_hp, :current_hp, :max_hp, :current_wounds, :max_wounds ]
      params.expect(character: [
        :name,
        :race,
        :nimble_class,
        :level,
        :background,
        :description,
        :languages,
        {
          trait_set_attributes: trait_set_params_list,
          stats_attributes: [ stats_params_list ],
          skills_attributes: [ skills_params_list ]
        }
      ])
    end
end
