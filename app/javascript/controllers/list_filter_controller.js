import { Controller } from "@hotwired/stimulus"

// Filters a list as you type: rows carry data-list-filter-text with what to match.
export default class extends Controller {
  static targets = ["input", "row", "empty"]

  filter() {
    const q = this.inputTarget.value.trim().toLowerCase()
    let shown = 0
    this.rowTargets.forEach((row) => {
      const match = !q || row.dataset.listFilterText.includes(q)
      row.hidden = !match
      if (match) shown++
    })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = shown > 0
  }
}
