class TraitSet < ApplicationRecord
  serialize :resource_tracks, coder: JSON

  belongs_to :character

  validates :current_hp, :temp_hp, :current_wounds, :current_actions, :current_hit_dice, :current_mana, :current_resource,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :current_values_do_not_exceed_maxima
  validate :resource_track_values_do_not_exceed_maxima

  private
    def current_values_do_not_exceed_maxima
      {
        current_hp: :max_hp,
        current_wounds: :max_wounds,
        current_actions: :max_actions,
        current_hit_dice: :max_hit_dice,
        current_mana: :max_mana,
        current_resource: :max_resource
      }.each do |current_field, maximum_field|
        current_value = public_send(current_field)
        maximum_value = public_send(maximum_field)
        next if current_value.nil? || maximum_value.nil? || current_value <= maximum_value

        errors.add(current_field, "cannot exceed #{maximum_field.to_s.humanize.downcase}")
      end
    end

    def resource_track_values_do_not_exceed_maxima
      Array(resource_tracks).each do |track|
        current = track.to_h["current"]
        maximum = track.to_h["max"]
        next if current.blank?

        numeric_current = Integer(current, exception: false)
        if numeric_current.nil? || numeric_current.negative?
          errors.add(:resource_tracks, "#{track.to_h['name']} must be a non-negative whole number")
          next
        end
        next if maximum.blank? || numeric_current <= maximum.to_i

        errors.add(:resource_tracks, "#{track.to_h['name']} cannot exceed its maximum")
      end
    end
end
