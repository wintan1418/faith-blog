import { Controller } from "@hotwired/stimulus"

// Chess puzzle of the day. We open Lichess in a new tab for the actual
// solving (their UI does it best). On the user's word that they solved
// it, we record a GameAttempt; the score scales with puzzle rating.
export default class extends Controller {
  static targets = ["solveBtn", "feedback"]
  static values  = { solvedUrl: String, csrf: String, already: Boolean }

  openedExternal() {
    if (this.alreadyValue || !this.hasSolveBtnTarget) return
    // Once they leave, surface the 'I solved it' button as the primary action.
    this.solveBtnTarget.classList.add("is-primary")
  }

  async markSolved() {
    if (this.alreadyValue) return
    this.solveBtnTarget.disabled = true
    this.solveBtnTarget.textContent = "Recording…"
    try {
      const response = await fetch(this.solvedUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        credentials: "same-origin"
      })
      const payload = await response.json()
      if (payload.ok) {
        this.alreadyValue = true
        this.solveBtnTarget.textContent = `✓ +${payload.score} points · saved`
        this.solveBtnTarget.classList.add("fc-btn-primary")
        if (this.hasFeedbackTarget) {
          this.feedbackTarget.classList.remove("hidden")
          this.feedbackTarget.textContent = "Nice work. Come back tomorrow for the next puzzle."
        }
      } else {
        this.solveBtnTarget.textContent = "Couldn't record"
        if (this.hasFeedbackTarget) {
          this.feedbackTarget.classList.remove("hidden")
          this.feedbackTarget.textContent = payload.error || "Try again."
        }
      }
    } catch {
      this.solveBtnTarget.textContent = "Network error"
    }
  }
}
