import { Controller } from "@hotwired/stimulus"

// Toggles between a truncated breath body and the full version, in place,
// without leaving the feed.
export default class extends Controller {
  static targets = ["short", "full", "toggle"]

  expand(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasShortTarget || !this.hasFullTarget) return

    this.shortTarget.classList.add("hidden")
    this.fullTarget.classList.remove("hidden")
    if (this.hasToggleTarget) this.toggleTarget.remove()
  }
}
