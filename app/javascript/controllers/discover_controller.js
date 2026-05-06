import { Controller } from "@hotwired/stimulus"

// Mobile bottom-sheet that exposes the feed sidebar cards
// (verse, golden breaths, prayer requests, trending, who-to-brethren)
// behind a "Discover" button next to the feed tabs.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.boundEsc = this.onEsc.bind(this)
    this.boundOutside = this.onOutsideClick.bind(this)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundEsc)
    document.removeEventListener("mousedown", this.boundOutside, true)
    document.body.classList.remove("fc-discover-open")
  }

  open(event) {
    if (event) event.preventDefault()
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.add("is-open")
    document.body.classList.add("fc-discover-open")
    document.addEventListener("keydown", this.boundEsc)
    // Delay outside-click so the same click that opened doesn't immediately close.
    setTimeout(() => document.addEventListener("mousedown", this.boundOutside, true), 50)
  }

  close(event) {
    if (event) event.preventDefault()
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.remove("is-open")
    document.body.classList.remove("fc-discover-open")
    document.removeEventListener("keydown", this.boundEsc)
    document.removeEventListener("mousedown", this.boundOutside, true)
  }

  onOutsideClick(event) {
    if (this.panelTarget.contains(event.target)) return
    // Ignore clicks on the trigger button itself (re-open prevention).
    if (event.target.closest(".fc-discover-trigger")) return
    this.close()
  }

  onEsc(event) {
    if (event.key === "Escape") this.close()
  }
}
