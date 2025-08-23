module SpellsHelper
  def name_of_tier(tier)
    case tier
    when 0
      "Cantrip"
    when -1
      "Utility"
    else
      value.to_s
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
end
