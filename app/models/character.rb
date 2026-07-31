class Character < ApplicationRecord
  # Nimble creation-time stat arrays (02-rules-canon.md S-1 #1). The two
  # highest values go to the class's 2 Key Stats, the remaining two to the
  # 2 Secondary Stats.
  STAT_ARRAYS = {
    "standard" => [ 2, 2, 0, -1 ],
    "balanced" => [ 2, 1, 1, 0 ],
    "min_max"  => [ 3, 1, -1, -1 ]
  }.freeze

  has_one :stat_set, dependent: :destroy
  has_one :skill_set, dependent: :destroy
  has_one :trait_set, dependent: :destroy

  accepts_nested_attributes_for :stat_set
  accepts_nested_attributes_for :skill_set
  accepts_nested_attributes_for :trait_set

  has_many :character_spells
  has_many :spells, through: :character_spells

  # Rules-canon references (spec 02/05). Optional at the model level because
  # 3 pre-existing characters predate this slice of canon and were never
  # backfilled with a guess; the creation flow is what actually requires
  # them (see #legal_for_creation? and CharactersController).
  belongs_to :character_class, optional: true
  belongs_to :ancestry, optional: true
  belongs_to :background, optional: true

  validates :stat_array, inclusion: { in: STAT_ARRAYS.keys }, allow_nil: true
  validate :background_prerequisite_satisfied

  before_create :ensure_defaults

  # A character is only a legal Nimble starting character (spec 05 TBD-1
  # "mandatory" list) once class, ancestry, background, and stat array are
  # all chosen and the background's prerequisite (if any) is met. This does
  # not yet implement the full draft/PlayableValid lifecycle from
  # 04-character-lifecycle.md -- it's the legality *check* that lifecycle
  # will gate on.
  def legal_for_creation?
    character_class.present? && ancestry.present? && background.present? &&
      stat_array.present? && errors[:background].empty?
  end

  def ensure_defaults
    build_default_stat_set if not stat_set
    build_default_skill_set if not skill_set
    build_default_trait_set if not trait_set
  end

  private
    def background_prerequisite_satisfied
      return if background.blank? || background.prerequisite_stat.blank?

      # stat_set may not be built yet on a brand-new record; apply the
      # chosen array first so the prerequisite can be checked against the
      # values creation would actually produce.
      candidate_stat_set = stat_set || build_projected_stat_set
      return if background.satisfied_by?(candidate_stat_set)

      errors.add(:background, "requires #{background.prerequisite_stat} <= #{background.prerequisite_max}")
    end

    def build_projected_stat_set
      return nil unless character_class.present? && stat_array.present?

      StatSet.new(projected_stat_values)
    end

    def projected_stat_values
      values = Array(STAT_ARRAYS[stat_array]).sort.reverse
      keys = character_class.key_stats
      secondaries = character_class.secondary_stats

      { keys[0] => values[0], keys[1] => values[1],
        secondaries[0] => values[2], secondaries[1] => values[3] }.symbolize_keys
    end

    def build_default_stat_set
      if character_class.present? && stat_array.present?
        build_stat_set(projected_stat_values)
      else
        build_stat_set strength: 0,
                        dexterity: 0,
                        intelligence: 0,
                        will: 0
      end
    end

    def build_default_skill_set
      build_skill_set arcana: 0,
                      insight: 0,
                      examination: 0,
                      finesse: 0,
                      might: 0,
                      lore: 0,
                      influence: 0,
                      naturecraft: 0,
                      stealth: 0,
                      perception: 0
    end

    def build_default_trait_set
      hit_die = character_class&.hit_die || "1d6"
      starting_hp = character_class&.starting_hp || 10

      build_trait_set initiative:        0,
                      speed:             30,
                      hit_die:           hit_die,
                      current_hit_dice:  1,
                      max_hit_dice:      1,
                      current_actions:   3,
                      max_actions:       3,
                      armor:             0,
                      temp_hp:           0,
                      current_hp:        starting_hp,
                      max_hp:            starting_hp,
                      current_wounds:    6,
                      max_wounds:        6
    end
end
