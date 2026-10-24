import { Controller } from "@hotwired/stimulus"

// Show / hide a password, and (on sign-up) a simple strength meter.
export default class extends Controller {
  static targets = ["input", "toggle", "meter", "label"]

  toggle() {
    const showing = this.inputTarget.type === "text"
    this.inputTarget.type = showing ? "password" : "text"
    this.toggleTarget.textContent = showing ? "Show" : "Hide"
    this.toggleTarget.setAttribute("aria-pressed", String(!showing))
    this.toggleTarget.setAttribute("aria-label", showing ? "Show password" : "Hide password")
    this.inputTarget.focus()
  }

  measure() {
    if (!this.hasMeterTarget) return
    const v = this.inputTarget.value
    let score = 0
    if (v.length >= 8) score++
    if (v.length >= 12) score++
    if (/[a-z]/.test(v) && /[A-Z]/.test(v)) score++
    if (/\d/.test(v) && /[^A-Za-z0-9]/.test(v)) score++
    if (v.length < 8) score = Math.min(score, 1)

    const words = ["Use 8 or more characters", "Weak", "Okay", "Good", "Strong"]
    this.meterTarget.dataset.level = v.length === 0 ? 0 : Math.max(1, score)
    if (this.hasLabelTarget) this.labelTarget.textContent = v.length === 0 ? words[0] : (v.length < 8 ? "Too short" : words[Math.max(1, score)])
  }
}
