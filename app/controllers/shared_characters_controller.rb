class SharedCharactersController < ApplicationController
  def show
    @share = CharacterShare.includes(:campaign, character: [ :character_class, :ancestry, :background, :stat_set, :skill_set, :trait_set, :spells, :story_subclass_changes ]).find_by!(share_token: params.expect(:token))
    @character = @share.character
    @can_approve_story_subclass = @share.campaign.gm?(current_account)
    @story_subclass_options = if @can_approve_story_subclass && @character.playable? && @character.subclass_name.present?
      @character.character_class&.story_based_subclass_options.to_a - [ @character.subclass_name ]
    else
      []
    end
    @story_subclass_changes = @character.story_subclass_changes.includes(:approved_by_account, :character_revision).order(created_at: :desc)
  end
end
