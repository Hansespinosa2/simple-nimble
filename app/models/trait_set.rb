class TraitSet < ApplicationRecord
  belongs_to :character

  validates :current_hp, :temp_hp, :current_wounds, :current_actions, :current_hit_dice,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :current_values_do_not_exceed_maxima

  private
    def current_values_do_not_exceed_maxima
      {
        current_hp: :max_hp,
        current_wounds: :max_wounds,
        current_actions: :max_actions,
        current_hit_dice: :max_hit_dice
      }.each do |current_field, maximum_field|
        current_value = public_send(current_field)
        maximum_value = public_send(maximum_field)
        next if current_value.nil? || maximum_value.nil? || current_value <= maximum_value

        errors.add(current_field, "cannot exceed #{maximum_field.to_s.humanize.downcase}")
      end
    end
end
