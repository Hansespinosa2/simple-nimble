class LevelUpService
  def self.finalize!(level_up)
    character = level_up.character
    character.with_lock do
      level_up.reload
      planner = LevelUpPlanner.new(character, level_up)
      fail_level_up!(level_up, planner) unless planner.valid?

      character.update!(status: "level_up") if character.playable?
      preview = planner.preview
      apply_preview!(character, preview)
      character.apply_level_up_transition!(preview.fetch("level"))
      character.update!(languages: preview.fetch("languages").join(", "))
      character.sync_granted_utility_spells!(level: preview.fetch("level"), ledger: character.spell_choice_ledger)
      level_up.update!(status: "finalized", preview: preview, finalized_at: Time.current)
      character.record_revision!(
        event_type: "level_up",
        summary: "Advanced to level #{character.level}",
        from_level: level_up.from_level,
        to_level: level_up.to_level
      )
    end

    level_up
  rescue ActiveRecord::RecordInvalid
    raise
  end

  def self.apply_preview!(character, preview)
    character.stat_set.update!(preview.fetch("stats"))
    character.skill_set.update!(preview.fetch("skills"))
    feature_choice_ledger = character.feature_choice_ledger
    level_key = preview.fetch("level").to_i.to_s
    preview.fetch("feature_choices").each do |pool_name, selections|
      feature_choice_ledger[pool_name] ||= {}
      feature_choice_ledger[pool_name][level_key] = Array(selections)
    end
    character.update!(feature_choices: feature_choice_ledger)

    spell_choice_ledger = character.spell_choice_ledger
    level_key = preview.fetch("level").to_i.to_s
    preview.fetch("spell_choices").each do |pool_name, selections|
      spell_choice_ledger[pool_name] ||= {}
      spell_choice_ledger[pool_name][level_key] = Array(selections)
    end
    character.update!(spell_choices: spell_choice_ledger)

    character.update!(
      language_choices: preview.fetch("language_choices"),
      feature_language_choices: preview.fetch("feature_language_choices")
    )

    trait_updates = preview.fetch("traits").slice(
      "max_hp", "current_hp", "max_hit_dice", "current_hit_dice", "max_actions", "initiative", "speed", "hit_die", "armor", "inventory_slots",
      "current_wounds", "max_wounds",
      "save_dc", "max_mana", "current_mana", "resource_name", "resource_formula", "resource_die", "max_resource", "current_resource", "resource_tracks"
    )
    character.update!(subclass_name: preview.fetch("subclass")) if preview.fetch("subclass").present?
    character.trait_set.update!(trait_updates)
  end
  private_class_method :apply_preview!

  def self.fail_level_up!(level_up, planner)
    planner.explanations.each { |explanation| level_up.errors.add(:base, explanation.fetch(:message)) }
    raise ActiveRecord::RecordInvalid, level_up
  end
  private_class_method :fail_level_up!
end
