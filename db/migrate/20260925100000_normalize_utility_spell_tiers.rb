class NormalizeUtilitySpellTiers < ActiveRecord::Migration[8.1]
  UTILITY_SPELL_NAMES = %w[
    Ice\ Disk Chillcraft Wintry\ Scrying Firebrand Fire\ Step Kindle Spark\ Buddy Spark\ Step
    Tempest's\ Command Light Beautify Bond\ of\ Peace Wind\ Whisper Helpful\ Gust Feather\ Fall
    Gravecraft False\ Face Thought\ Leech
  ].freeze

  def up
    update_spell_tier(0, "Core Rules 2.0.1, pp. 52–53")
  end

  def down
    update_spell_tier(-1, "Core Rules 2.0.1, Spells")
  end

  private

  def update_spell_tier(tier, source_ref)
    names = UTILITY_SPELL_NAMES.map { |name| connection.quote(name) }.join(", ")
    execute <<~SQL
      UPDATE spells
      SET tier = #{Integer(tier)}, mana_cost = 0, source_ref = #{connection.quote(source_ref)}
      WHERE name IN (#{names})
    SQL
  end
end
