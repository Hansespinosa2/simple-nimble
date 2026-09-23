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
      character.update!(level: preview.fetch("level"), status: "playable")
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

    trait_updates = preview.fetch("traits").slice(
      "max_hp", "current_hp", "max_hit_dice", "current_hit_dice", "initiative", "armor", "inventory_slots",
      "save_dc", "max_mana", "current_mana", "resource_name", "resource_formula", "resource_die", "max_resource", "current_resource"
    )
    character.trait_set.update!(trait_updates)
  end
  private_class_method :apply_preview!

  def self.fail_level_up!(level_up, planner)
    planner.explanations.each { |explanation| level_up.errors.add(:base, explanation.fetch(:message)) }
    raise ActiveRecord::RecordInvalid, level_up
  end
  private_class_method :fail_level_up!
end
