class StorySubclassChange < ApplicationRecord
  serialize :subclass_choices, coder: JSON

  belongs_to :character
  belongs_to :campaign
  belongs_to :approved_by_account, class_name: "Account"
  belongs_to :character_revision

  validates :from_subclass, :to_subclass, :story_note, :source_ref, presence: true
  validates :story_note, length: { maximum: 1_000 }
  validate :subclass_is_a_story_option_for_character_class
  validate :approver_is_a_gm_for_campaign
  validate :revision_records_this_character_change
  validate :subclass_is_replaced

  private
    def subclass_is_a_story_option_for_character_class
      rule = character&.character_class&.story_based_subclass_rule(to_subclass)
      return if rule.present? && rule.fetch("source_ref") == source_ref

      errors.add(:to_subclass, "must be a story-based subclass for this character's class")
    end

    def approver_is_a_gm_for_campaign
      return if campaign&.gm?(approved_by_account)

      errors.add(:approved_by_account, "must be a GM in this campaign")
    end

    def revision_records_this_character_change
      return if character_revision&.character == character && character_revision.event_type == "story_subclass_change"

      errors.add(:character_revision, "must record this character's story subclass change")
    end

    def subclass_is_replaced
      return if from_subclass.present? && from_subclass != to_subclass

      errors.add(:to_subclass, "must replace a different existing subclass")
    end
end
