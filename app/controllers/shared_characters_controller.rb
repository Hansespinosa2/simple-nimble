class SharedCharactersController < ApplicationController
  def show
    @share = CharacterShare.includes(:campaign, character: [ :character_class, :ancestry, :background, :stat_set, :skill_set, :trait_set, :spells, :story_subclass_changes ]).find_by!(share_token: params.expect(:token))
    unless @share.campaign.member?(current_account)
      if current_account.present?
        redirect_to campaigns_path, alert: "You need campaign access to view this shared sheet."
      else
        redirect_to new_session_path, alert: "Create a workspace profile and join this campaign to view the shared sheet."
      end
      return
    end

    @character = @share.character
    @can_approve_story_subclass = @share.campaign.gm?(current_account)
    @story_subclass_options = if @can_approve_story_subclass && @character.playable? && @character.subclass_name.present?
      @character.character_class&.story_based_subclass_options.to_a - [ @character.subclass_name ]
    else
      []
    end
    @story_subclass_spell_choice_pools = @story_subclass_options.flat_map do |subclass_name|
      @character.story_subclass_spell_choice_pools_through(subclass_name:)
    end
    @story_subclass_feature_choice_pools = @story_subclass_options.flat_map do |subclass_name|
      @character.story_subclass_feature_choice_pools_through(subclass_name:)
    end
    @story_subclass_companion_rule = @story_subclass_options.filter_map do |subclass_name|
      @character.story_subclass_companion_rule(subclass_name)
    end.first
    @story_subclass_changes = @character.story_subclass_changes.includes(:approved_by_account, :character_revision).order(created_at: :desc)
  end
end
