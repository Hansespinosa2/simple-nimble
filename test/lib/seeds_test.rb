require "test_helper"

# S-02:AC-1 S-05:AC-6 S-06:AC-8 S-09:AC-2 S-09:AC-3
class SeedsTest < ActiveSupport::TestCase
  test "loading the canonical seed data twice does not duplicate records" do
    Rails.application.load_seed
    counts_after_first_load = canonical_counts

    Rails.application.load_seed

    assert_equal counts_after_first_load, canonical_counts
    assert_equal 11, CharacterClass.where(name: canonical_class_names).count
    assert_equal 24, Ancestry.where.not(name: [ "MyString" ]).count
    assert_equal 14, Spell.where(name: canonical_spell_names).count
    assert Character.find_by!(name: "Mira Ashfall").playable?
  end

  private
    def canonical_counts
      {
        classes: CharacterClass.where(name: canonical_class_names).count,
        ancestries: Ancestry.where.not(name: [ "MyString" ]).count,
        backgrounds: Background.where.not(name: [ "MyString" ]).count,
        spells: Spell.where(name: canonical_spell_names).count,
        demo_characters: Character.where(name: %w[Gorn Luna\ Banana-Hammock David\ Andersen Mira\ Ashfall]).count
      }
    end

    def canonical_class_names
      %w[Berserker The\ Cheat Commander Hunter Mage Oathsworn Shadowmancer Shepherd Songweaver Stormshifter Zephyr]
    end

    def canonical_spell_names
      %w[
        Flame\ Dart Heart's\ Fire Ignite Enchant\ Weapon Flame\ Barrier Pyroclasm Fiery\ Embrace Living\ Inferno Dragonform
        Ice\ Lance Zap Razor\ Wind Rebuke Entice
      ]
    end
end
