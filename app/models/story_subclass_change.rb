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

  def subclass_choice_entries
    choices = subclass_choices.to_h.stringify_keys
    source_refs = choices.fetch("source_refs", {}).to_h.stringify_keys
    entries = []
    companion = choices.fetch("companion", {}).to_h.stringify_keys
    if companion.present?
      entries << {
        label: "Companion",
        value: [ companion["size"], companion["name"] ].compact_blank.join(" "),
        source_refs: Array(source_refs.fetch("companion", source_ref))
      }
    end

    %w[replaced_feature_choices feature_choices spell_choices].each do |choice_kind|
      choices.fetch(choice_kind, {}).to_h.each do |pool_name, choices_by_level|
        choices_by_level.to_h.each do |level, selections|
          entries << {
            label: "#{'Replaced · ' if choice_kind == 'replaced_feature_choices'}Level #{level} · #{pool_name}",
            value: Array(selections).join(", "),
            source_refs: Array(source_refs.fetch(choice_kind, {}).to_h.fetch(pool_name, source_ref))
          }
        end
      end
    end

    choices.fetch("replaced_resource_pools", {}).to_h.each do |pool_key, resource|
      resource = resource.to_h.stringify_keys
      entries << {
        label: "Replaced resource · #{resource.fetch('name')}",
        value: "#{resource.fetch('current')} / #{resource['max']}",
        source_refs: Array(source_refs.fetch("replaced_resource_pools", {}).to_h.fetch(pool_key, resource["source_ref"] || source_ref))
      }
    end

    choices.fetch("replaced_spells", []).each do |spell_name|
      entries << {
        label: "No longer castable",
        value: spell_name,
        source_refs: Array(source_refs.fetch("replaced_spells", {}).to_h.fetch(spell_name, source_ref))
      }
    end

    entries
  end

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
