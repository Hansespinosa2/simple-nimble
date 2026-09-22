import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "characterClass", "ancestry", "background", "statArray", "classHint", "ancestryHint", "backgroundHint",
    "rulesCallout", "hpPreview", "armorPreview", "initiativePreview", "hitDiePreview", "languagesPreview",
    "speedPreview", "woundsPreview", "previewNote", "skillBudget"
  ]

  static values = { rules: Object }

  connect() {
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

    this.updateStats(characterClass, array)
    this.updateSkills(characterClass, ancestry, array)
    this.updateDerived(characterClass, ancestry, array)
    this.updateHints(characterClass, ancestry, background)
    this.updateSkillBudget()
  }

  updateStats(characterClass, array) {
    const statValues = {}
    const sortedArray = array ? [...array].sort((a, b) => b - a) : []
    const stats = [ "strength", "dexterity", "intelligence", "will" ]
    const keys = characterClass?.key_stats || []
    const secondaries = characterClass?.secondary_stats || []

    keys.forEach((stat, index) => { statValues[stat] = sortedArray[index] })
    secondaries.forEach((stat, index) => { statValues[stat] = sortedArray[index + keys.length] })

    this.element.querySelectorAll("[data-stat-value]").forEach((node) => {
      const stat = node.dataset.statValue
      node.textContent = statValues[stat] === undefined ? "—" : this.signed(statValues[stat])
      const role = this.element.querySelector(`[data-stat-role='${stat}']`)
      if (role) role.textContent = keys.includes(stat) ? "Key Stat" : "Secondary"
    })

    this.statValues = statValues
  }

  updateSkills(characterClass, ancestry, array) {
    const statValues = this.statValues || {}
    const bonus = ancestry?.all_skills_bonus || 0
    const mapping = {
      arcana: "intelligence", examination: "intelligence", finesse: "dexterity", influence: "will",
      insight: "will", lore: "intelligence", might: "strength", naturecraft: "will",
      perception: "will", stealth: "dexterity"
    }

    this.element.querySelectorAll("[data-skill]").forEach((input) => {
      const skill = input.dataset.skill
      const base = (statValues[mapping[skill]] || 0) + bonus
      const baseNode = this.element.querySelector(`[data-skill-base='${skill}']`)
      if (baseNode) baseNode.textContent = `base ${this.signed(base)}`
      if (!input.dataset.touched) input.value = base
    })
  }

  updateDerived(characterClass, ancestry, array) {
    const stats = this.statValues || {}
    const dexterity = stats.dexterity || 0
    const intelligence = stats.intelligence || 0
    const initiative = dexterity + (ancestry?.initiative_modifier || 0)
    const armor = dexterity + (ancestry?.armor_modifier || 0)
    const speed = 30 + (ancestry?.speed_modifier || 0)
    const wounds = 6 + (ancestry?.max_wounds_modifier || 0)
    const languages = [ "Common" ]

    for (let index = 0; index < Math.max(intelligence, 0); index += 1) languages.push("+ language")

    this.setTargetText("hpPreview", characterClass?.starting_hp || "—")
    this.setTargetText("armorPreview", array ? armor : "—")
    this.setTargetText("initiativePreview", array ? this.signed(initiative) : "—")
    this.setTargetText("hitDiePreview", characterClass?.hit_die || "—")
    this.setTargetText("languagesPreview", array ? languages.join(", ") : "Common")
    this.setTargetText("speedPreview", array ? speed : "—")
    this.setTargetText("woundsPreview", array ? wounds : "—")
  }

  updateHints(characterClass, ancestry, background) {
    this.setTargetText("classHint", characterClass ? `${characterClass.key_stats.map(this.abbreviate).join(" + ")} Key Stats · ${characterClass.hit_die} · ${characterClass.starting_hp} starting HP` : "Two Key Stats shape your build.")
    this.setTargetText("ancestryHint", ancestry?.summary || "Ancestry traits apply automatically.")

    let backgroundHint = background?.description || "Backgrounds can have creation prerequisites."
    if (background?.prerequisite_stat) backgroundHint += ` Requires ${this.abbreviate(background.prerequisite_stat)} ≤ ${background.prerequisite_max}.`
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
