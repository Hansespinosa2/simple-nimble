import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "characterClass", "ancestry", "background", "statArray", "spellSchoolChoice", "spellSchoolChoiceField", "backgroundSpellChoice", "backgroundSpellChoiceField", "classHint", "ancestryHint", "backgroundHint",
    "rulesCallout", "hpPreview", "armorPreview", "initiativePreview", "hitDiePreview", "saveDcPreview", "manaPreview", "languagesPreview", "statAssignment", "startingEquipmentChoice", "startingEquipmentPreview",
    "speedPreview", "woundsPreview", "resourcePreview", "savesPreview", "previewNote", "skillBudget"
  ]

  static values = { rules: Object }

  connect() {
    this.spellSchoolChoiceInitialDisabled = this.hasSpellSchoolChoiceTarget && this.spellSchoolChoiceTarget.disabled
    this.backgroundSpellChoiceInitialDisabled = this.hasBackgroundSpellChoiceTarget && this.backgroundSpellChoiceTarget.disabled
    this.element.querySelectorAll("[data-skill]").forEach((input) => {
      input.addEventListener("input", () => {
        input.dataset.touched = "true"
        this.updateSkillBudget()
      })
    })
    this.refresh()
  }

  refresh() {
    const characterClass = this.rulesValue.classes?.[this.characterClassTarget.value]
    const ancestry = this.rulesValue.ancestries?.[this.ancestryTarget.value]
    const background = this.rulesValue.backgrounds?.[this.backgroundTarget.value]
    const array = this.rulesValue.stat_arrays?.[this.statArrayTarget.value]

    this.updateStatAssignmentOptions(array, characterClass)
    this.updateStats(characterClass, array)
    this.updateSkills(characterClass, ancestry, background, array)
    this.updateDerived(characterClass, ancestry, background, array)
    this.updateStartingEquipment(characterClass)
    this.updateHints(characterClass, ancestry, background)
    this.updateSpellSchoolChoice(characterClass)
    this.updateBackgroundSpellChoice(background)
    this.updateSkillBudget()
  }

  updateSpellSchoolChoice(characterClass) {
    if (!this.hasSpellSchoolChoiceFieldTarget) return

    const enabled = characterClass?.spell_schools?.includes("choice") || false
    this.spellSchoolChoiceFieldTarget.hidden = !enabled
    if (this.hasSpellSchoolChoiceTarget) this.spellSchoolChoiceTarget.disabled = this.spellSchoolChoiceInitialDisabled || !enabled
  }

  updateBackgroundSpellChoice(background) {
    if (!this.hasBackgroundSpellChoiceFieldTarget) return

    const enabled = background?.starting_spell_choice || false
    this.backgroundSpellChoiceFieldTarget.hidden = !enabled
    if (this.hasBackgroundSpellChoiceTarget) {
      if (!enabled) this.backgroundSpellChoiceTarget.value = ""
      this.backgroundSpellChoiceTarget.disabled = this.backgroundSpellChoiceInitialDisabled
    }
  }

  updateStartingEquipment(characterClass) {
    if (!this.hasStartingEquipmentPreviewTarget) return

    if (this.hasStartingEquipmentChoiceTarget && this.startingEquipmentChoiceTarget.value === "starting_gold") {
      const goldPerLevel = Number(this.rulesValue.starting_equipment?.gold_per_level || 50)
      const level = Number(this.element.querySelector("[data-character-builder-target='level']")?.value || 1)
      this.setTargetText("startingEquipmentPreview", `${goldPerLevel * Math.max(level, 1)} gp`)
    } else {
      this.setTargetText("startingEquipmentPreview", characterClass?.starting_gear?.join(", ") || "Choose a class to see its gear")
    }
  }

  updateStats(characterClass, array) {
    const statValues = {}
    const sortedArray = array ? [...array].sort((a, b) => b - a) : []
    const stats = [ "strength", "dexterity", "intelligence", "will" ]
    const keys = characterClass?.key_stats || []
    const secondaries = characterClass?.secondary_stats || []

    keys.forEach((stat, index) => { statValues[stat] = sortedArray[index] })
    secondaries.forEach((stat, index) => { statValues[stat] = sortedArray[index + keys.length] })

    this.element.querySelectorAll("[data-character-builder-target='statAssignment']").forEach((input) => {
      if (input.value !== "") statValues[input.dataset.stat] = Number(input.value)
    })

    this.element.querySelectorAll("[data-stat-value]").forEach((node) => {
      const stat = node.dataset.statValue
      node.textContent = statValues[stat] === undefined ? "—" : this.signed(statValues[stat])
      const role = this.element.querySelector(`[data-stat-role='${stat}']`)
      if (role) role.textContent = keys.includes(stat) ? "Key Stat" : "Secondary"
    })

    this.statValues = statValues
  }

  updateStatAssignmentOptions(array, characterClass) {
    const inputs = [...this.element.querySelectorAll("[data-character-builder-target='statAssignment']")]
    if (!inputs.length) return

    const arrayValues = (array || []).map(Number)
    const arrayKey = arrayValues.join(",")
    const arrayChanged = arrayKey !== this.lastStatArrayKey
    const classKey = characterClass?.name || ""
    const classChanged = classKey !== this.lastStatClassKey
    const options = [...new Set(arrayValues)].sort((a, b) => b - a)

    inputs.forEach((input) => {
      const previous = input.value
      input.innerHTML = '<option value="">Choose</option>'
      options.forEach((value) => {
        const option = document.createElement("option")
        option.value = value
        option.textContent = this.signed(value)
        input.appendChild(option)
      })
      if (previous !== "" && options.includes(Number(previous))) input.value = previous
    })

    if (arrayChanged || classChanged || (arrayValues.length && inputs.every((input) => input.value === ""))) {
      const sorted = [...arrayValues].sort((a, b) => b - a)
      const orderedStats = [...(characterClass?.key_stats || []), ...(characterClass?.secondary_stats || [])]
      const defaults = {}
      orderedStats.forEach((stat, index) => { defaults[stat] = sorted[index] ?? "" })
      inputs.forEach((input, index) => { input.value = defaults[input.dataset.stat] ?? sorted[index] ?? "" })
    }

    this.lastStatArrayKey = arrayKey
    this.lastStatClassKey = classKey
  }

  updateSkills(characterClass, ancestry, background, array) {
    const statValues = this.statValues || {}
    const allSkillsBonus = (ancestry?.all_skills_bonus || 0) + (background?.all_skills_bonus || 0)
    const mapping = {
      arcana: "intelligence", examination: "intelligence", finesse: "dexterity", influence: "will",
      insight: "will", lore: "intelligence", might: "strength", naturecraft: "will",
      perception: "will", stealth: "dexterity"
    }

    this.element.querySelectorAll("[data-skill]").forEach((input) => {
      const skill = input.dataset.skill
      const base = (statValues[mapping[skill]] || 0) + allSkillsBonus + (ancestry?.skill_modifiers?.[skill] || 0) + (background?.skill_modifiers?.[skill] || 0)
      const baseNode = this.element.querySelector(`[data-skill-base='${skill}']`)
      if (baseNode) baseNode.textContent = `base ${this.signed(base)}`
      if (!input.dataset.touched) input.value = base
    })
  }

  updateDerived(characterClass, ancestry, background, array) {
    const stats = this.statValues || {}
    const dexterity = stats.dexterity || 0
    const intelligence = stats.intelligence || 0
    const level = Number(this.element.querySelector("[data-character-builder-target='level']")?.value || 1)
    const initiative = dexterity + (ancestry?.initiative_modifier || 0) + (background?.initiative_modifier || 0)
    const armorRules = { ...(characterClass?.armor_rules || {}) }
    if (this.hasStartingEquipmentChoiceTarget && this.startingEquipmentChoiceTarget.value === "starting_gold") {
      armorRules.base = 0
      delete armorRules.dexterity_cap
    }
    const armor = this.armorValue(armorRules, stats) + (ancestry?.armor_modifier || 0) + (background?.armor_modifier || 0)
    const speed = 6 + (ancestry?.speed_modifier || 0) + (background?.speed_modifier || 0)
    const wounds = 6 + (ancestry?.max_wounds_modifier || 0) + (background?.max_wounds_modifier || 0)
    const keyStats = characterClass?.key_stats || []
    const saveDc = array && keyStats.length ? 10 + Math.max(...keyStats.map((stat) => stats[stat] || 0)) : "—"
    const saves = characterClass ? `${this.abbreviate(characterClass.save_bonus)}+ / ${this.abbreviate(characterClass.save_penalty)}−` : "—"
    const mana = array ? this.manaMax(characterClass?.resource, stats, level) : "—"
    const languages = [ "Common" ]

    if (intelligence >= 0) {
      languages.push(...(ancestry?.language_grants || []), ...(background?.language_grants || []))
    }

    for (let index = 0; index < Math.max(intelligence, 0); index += 1) languages.push("+ language")

    this.setTargetText("hpPreview", characterClass?.starting_hp || "—")
    this.setTargetText("armorPreview", array ? armor : "—")
    this.setTargetText("initiativePreview", array ? this.signed(initiative) : "—")
    this.setTargetText("hitDiePreview", characterClass?.hit_die || "—")
    this.setTargetText("saveDcPreview", saveDc)
    this.setTargetText("savesPreview", saves)
    this.setTargetText("manaPreview", mana)
    this.setTargetText("languagesPreview", array ? languages.join(", ") : "Common")
    this.setTargetText("speedPreview", array ? speed : "—")
    this.setTargetText("woundsPreview", array ? wounds : "—")
    this.setTargetText("resourcePreview", characterClass?.resource?.name || "—")
  }

  updateHints(characterClass, ancestry, background) {
    const resourceHint = characterClass?.resource?.name ? ` · ${characterClass.resource.name}` : ""
    const savesHint = characterClass ? ` · Saves ${this.abbreviate(characterClass.save_bonus)}+ / ${this.abbreviate(characterClass.save_penalty)}−` : ""
    this.setTargetText("classHint", characterClass ? `${characterClass.key_stats.map(this.abbreviate).join(" + ")} Key Stats · ${characterClass.hit_die} · ${characterClass.starting_hp} starting HP${savesHint}${resourceHint}` : "Two Key Stats shape your build.")
    this.setTargetText("ancestryHint", ancestry?.summary || "Ancestry traits apply automatically.")

    let backgroundHint = background?.description || "Backgrounds can have creation prerequisites."
    if (background?.prerequisite_stat) backgroundHint += ` Requires ${this.abbreviate(background.prerequisite_stat)} ≤ ${background.prerequisite_max}.`
    if (background?.starting_spell_choice) backgroundHint += " Grants 1 Utility Spell."
    this.setTargetText("backgroundHint", backgroundHint)

    if (this.hasRulesCalloutTarget) {
      if (background?.prerequisite_stat) {
        this.rulesCalloutTarget.innerHTML = `<span class="callout-icon">!</span><span>This background checks ${this.abbreviate(background.prerequisite_stat)} ≤ ${background.prerequisite_max} when you finalize.</span>`
        this.rulesCalloutTarget.classList.add("rules-callout-warning")
      } else if (characterClass && ancestry && background) {
        this.rulesCalloutTarget.innerHTML = `<span class="callout-icon">✦</span><span>Great foundation. Your derived values are ready to review before you finalize.</span>`
        this.rulesCalloutTarget.classList.remove("rules-callout-warning")
      }
    }
    this.setTargetText("previewNote", characterClass && ancestry && background ? "Changes are preview-only until you save." : "Choose the four rules decisions to unlock your preview.")
  }

  updateSkillBudget() {
    if (!this.hasSkillBudgetTarget) return

    const level = Number(this.element.querySelector("[data-character-builder-target='level']")?.value || 1)
    const budget = 4 + Math.max(level - 1, 0)
    let spent = 0
    this.element.querySelectorAll("[data-skill]").forEach((input) => {
      const baseNode = this.element.querySelector(`[data-skill-base='${input.dataset.skill}']`)
      const base = Number(baseNode?.textContent.match(/-?\d+/)?.[0] || 0)
      spent += Math.max(Number(input.value || 0) - base, 0)
    })
    this.skillBudgetTarget.innerHTML = `Spend <strong>${spent}/${budget}</strong> extra points`
    this.skillBudgetTarget.classList.toggle("over-budget", spent > budget)
  }

  setTargetText(target, text) {
    if (this[`has${this.capitalize(target)}Target`]) this[`${target}Target`].textContent = text
  }

  manaMax(resource, stats, level) {
    if (level < Number(resource?.max_start_level || 1)) return "—"

    const formula = resource?.max_formula?.split(";")[0] || ""
    const match = formula.match(/(?:mana\s+)?(STR|DEX|INT|WIL)\s*(?:\*\s*(\d+))?\s*\+\s*LVL/i)
    if (!match) return "—"

    const stat = { STR: "strength", DEX: "dexterity", INT: "intelligence", WIL: "will" }[match[1].toUpperCase()]
    const multiplier = Number(match[2] || 1)
    return (stats[stat] || 0) * multiplier + level
  }

  armorValue(rules, stats) {
    const base = Number(rules?.base || 0)
    const dexterity = stats.dexterity || 0
    if (rules?.formula === "dexterity_plus_strength") return base + dexterity + (stats.strength || 0)

    const cap = rules?.dexterity_cap
    return base + (cap === undefined ? dexterity : Math.min(dexterity, Number(cap)))
  }

  signed(value) {
    return value > 0 ? `+${value}` : `${value}`
  }

  abbreviate(stat) {
    return { strength: "STR", dexterity: "DEX", intelligence: "INT", will: "WIL" }[stat] || stat
  }

  capitalize(value) {
    return value.charAt(0).toUpperCase() + value.slice(1)
  }
}
