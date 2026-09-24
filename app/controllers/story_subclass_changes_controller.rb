class StorySubclassChangesController < ApplicationController
  def create
    share = CharacterShare.includes(:campaign, :character).find_by!(share_token: params.expect(:token))
    return head :forbidden unless share.campaign.gm?(current_account)

    attributes = params.expect(story_subclass_change: [ :current_subclass, :to_subclass, :story_note, :companion_name, :companion_size, { spell_choices: {}, feature_choices: {} } ])
    StorySubclassChangeService.call(
      character: share.character,
      share:,
      approved_by: current_account,
      current_subclass: attributes[:current_subclass],
      to_subclass: attributes[:to_subclass],
      story_note: attributes[:story_note],
      spell_choices: attributes[:spell_choices] || {},
      feature_choices: attributes[:feature_choices] || {},
      companion_name: attributes[:companion_name],
      companion_size: attributes[:companion_size]
    )
    redirect_to shared_character_path(share.share_token), notice: "Story subclass change recorded in the character history."
  rescue ArgumentError => error
    redirect_to shared_character_path(share.share_token), alert: error.message
  rescue ActiveRecord::RecordInvalid => error
    redirect_to shared_character_path(share.share_token), alert: error.record.errors.full_messages.to_sentence
  end
end
