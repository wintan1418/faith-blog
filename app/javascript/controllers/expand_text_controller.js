import { Controller } from "@hotwired/stimulus"

// Toggles between a truncated breath body and the full version, in place,
// without leaving the feed. Uses inline style.display so site CSS for
// .fc-breath-copy can't beat the hide rule on specificity.
export default class extends Controller {
  static targets = ["short", "full", "toggle"]

  connect() {
    if (this.hasFullTarget) this.fullTarget.style.display = "none"
  }

  expand(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasShortTarget || !this.hasFullTarget) return

    this.shortTarget.style.display = "none"
    this.fullTarget.style.display = ""
    if (this.hasToggleTarget) this.toggleTarget.remove()
  }
}
