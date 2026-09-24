class StorySubclassChangeService
  MAX_STORY_NOTE_LENGTH = 1_000

  def self.call(character:, share:, approved_by:, current_subclass:, to_subclass:, story_note:)
    note = story_note.to_s.strip
    raise ArgumentError, "Add a story note explaining why the subclass changes." if note.blank?
    raise ArgumentError, "Story notes must be #{MAX_STORY_NOTE_LENGTH} characters or fewer." if note.length > MAX_STORY_NOTE_LENGTH

    change = nil
    character.with_lock do
      current_share = CharacterShare.find_by(id: share.id, character_id: character.id, campaign_id: share.campaign_id)
      raise ArgumentError, "This shared sheet is no longer available." unless current_share&.permission == "read"
      raise ArgumentError, "Only this campaign's GM can approve a story subclass change." unless current_share.campaign.gm?(approved_by)
      raise ArgumentError, "This sheet changed since you opened it. Refresh and try again." unless character.subclass_name == current_subclass.to_s
      raise ArgumentError, "A story-based subclass can only replace an existing subclass." if character.subclass_name.blank?
      raise ArgumentError, "Choose a different subclass from the one currently recorded." if character.subclass_name == to_subclass.to_s

      story_rule = character.character_class&.story_based_subclass_rule(to_subclass)
      raise ArgumentError, "#{to_subclass} is not a story-based subclass for this character's class." unless story_rule

      from_subclass = character.subclass_name
      character.with_approved_story_subclass_change(
        from_subclass:,
        to_subclass:,
        story_note: note,
        campaign: current_share.campaign,
        approved_by:
      ) do
        character.subclass_name = to_subclass
        character.save!

        revision = character.record_revision!(
          event_type: "story_subclass_change",
          summary: "#{approved_by.display_name} approved #{from_subclass} → #{to_subclass}. Story: #{note}",
          from_level: character.level,
          to_level: character.level
        )
        change = character.story_subclass_changes.create!(
          campaign: current_share.campaign,
          approved_by_account: approved_by,
          character_revision: revision,
          from_subclass:,
          to_subclass:,
          story_note: note,
          source_ref: story_rule.fetch("source_ref")
        )
      end
    end

    change
  end
end
