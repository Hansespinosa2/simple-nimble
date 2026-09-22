class SharedCharactersController < ApplicationController
  def show
    @share = CharacterShare.includes(:campaign, character: [ :character_class, :ancestry, :background, :stat_set, :skill_set, :trait_set, :spells ]).find_by!(share_token: params.expect(:token))
    @character = @share.character
  end
end
