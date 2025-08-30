module SpellsHelper
  def name_of_tier(tier)
    case tier
    when 0
      "Cantrip"
    when -1
      "Utility"
    else
      "Tier " + tier.to_s
    end
  end

  def name_of_action_cost(action_cost)
    action_cost.to_s
  end

  def name_of_target(target)
    case target
    when 0
      "Self"
    when 99
      "AoE"
    else
      "#{target} #{pluralize(target, 'target')}"
    end
  end

  def name_of_range(range)
    range.to_s
  end

  def name_of_casting_time(casting_time)
    case casting_time
    when 0
      "Instant"
    else
      casting_time.to_s + " minutes"
    end
  end

  def color_from_spell_school(spell_school)
    school_to_spell = {
      "Fire" =>       "text-red-700",
      "Ice" =>        "text-blue-300",
      "Lightning" =>  "text-indigo-700",
      "Wind" =>       "text-green-700",
      "Radiant" =>    "text-yellow-600",
      "Necrotic" =>   "text-purple-700"
    }

    school_to_spell.fetch(spell_school.capitalize, "text-black")
  end
end
