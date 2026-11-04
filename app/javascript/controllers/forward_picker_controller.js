import { Controller } from "@hotwired/stimulus"

// The "Forward to…" list: search chats, tick up to five, then Forward.
export default class extends Controller {
  static targets = ["row", "box", "counter", "send"]
  static values = { limit: { type: Number, default: 5 } }

  filter(event) {
    const q = event.target.value.trim().toLowerCase()
    this.rowTargets.forEach(row => { row.hidden = q !== "" && !row.dataset.name.includes(q) })
  }

  count() {
    const chosen = this.boxTargets.filter(b => b.checked).length
    // At the limit, the rest can't be ticked.
    this.boxTargets.forEach(b => { b.disabled = !b.checked && chosen >= this.limitValue })
    this.sendTarget.disabled = chosen === 0
    this.counterTarget.textContent = chosen === 0
      ? `Choose up to ${this.limitValue} chats`
      : `${chosen} chosen${chosen >= this.limitValue ? " (the most at once)" : ""}`
  }
}
