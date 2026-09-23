class LevelUpsController < ApplicationController
  before_action :set_character
  before_action :require_character_owner
  before_action :set_level_up, only: %i[show update]

  def new
    unless @character.level_up_eligible?
      redirect_to @character, alert: "Only a playable, legal character can start a level-up."
      return
    end

    @level_up = @character.level_ups.build(from_level: @character.level, to_level: @character.level + 1)
    @planner = LevelUpPlanner.new(@character, @level_up)
  end

  def create
    @level_up = @character.level_ups.build(level_up_params)
    @level_up.from_level ||= @character.level
    @level_up.to_level ||= @character.level.to_i + 1
    @planner = LevelUpPlanner.new(@character, @level_up)
    save_level_up
  end

  def show
    @planner = LevelUpPlanner.new(@character, @level_up)
  end

  def update
    @level_up.assign_attributes(level_up_params)
    @planner = LevelUpPlanner.new(@character, @level_up)
    save_level_up
  end

  private
    def set_character
      @character = Character.find(params.expect(:character_id))
    end

    def require_character_owner
      return if current_account.blank? && @character.account.blank?
      return if current_account.present? && @character.account == current_account

      redirect_to @character, alert: "Only the player who owns this character can level it up."
    end

    def set_level_up
      @level_up = @character.level_ups.find(params.expect(:id))
    end

    def level_up_params
      params.expect(level_up: [ :from_level, :to_level, :skill_name, :skill_from, :stat_name, :second_stat_name, :subclass_name, :hit_die_roll_one, :hit_die_roll_two, :notes ])
    end

    def save_level_up
      @level_up.preview = @planner.preview
      if @level_up.save
        if finalize_requested?
          begin
            LevelUpService.finalize!(@level_up)
            redirect_to @character, notice: "Level-up complete. #{@character.name.presence || 'Your character'} is now level #{@character.reload.level}."
          rescue ActiveRecord::RecordInvalid
            @planner = LevelUpPlanner.new(@character, @level_up)
            render :show, status: :unprocessable_entity
          end
        else
          @character.update!(status: "level_up") if @character.playable?
          redirect_to character_level_up_path(@character, @level_up), notice: "Level-up draft saved. Nothing changes until you apply it."
        end
      else
        add_planner_errors
        render(@level_up.persisted? ? :show : :new, status: :unprocessable_entity)
      end
    end

    def add_planner_errors
      @planner.explanations.each do |explanation|
        @level_up.errors.add(:base, explanation.fetch(:message))
      end
    end

    def finalize_requested?
      params[:finalize].present? || params[:commit].to_s.downcase.include?("apply")
    end
end
