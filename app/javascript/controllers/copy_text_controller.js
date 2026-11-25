import { Controller } from "@hotwired/stimulus"

// A "Copy" button for a block of text (recovery codes).
export default class extends Controller {
  static targets = ["button"]
  static values = { text: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.flash("Copied")
    } catch {
      this.flash("Select and copy them instead")
    }
  }

  flash(label) {
    if (!this.hasButtonTarget) return
    const before = this.buttonTarget.dataset.label || this.buttonTarget.textContent
    this.buttonTarget.dataset.label = before
    this.buttonTarget.textContent = label
    setTimeout(() => { this.buttonTarget.textContent = before }, 2000)
  }
}
