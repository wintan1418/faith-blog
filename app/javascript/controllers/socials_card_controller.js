import { Controller } from "@hotwired/stimulus"
import { rememberDismissal } from "../remember_dismissal"

// The feed's "Follow Brethreign" card: shown once. Once it has been on screen
// for a moment it's remembered on the account (it stays for this visit);
// closing it or tapping one of its links hides it straight away.
export default class extends Controller {
  static values = { key: String }

  connect() {
    if (!("IntersectionObserver" in window)) return
    this.observer = new IntersectionObserver((entries) => {
      const visible = entries.some((e) => e.isIntersecting)
      clearTimeout(this.timer)
      if (visible) this.timer = setTimeout(() => this.remember(), 1500)
    }, { threshold: 0.6 })
    this.observer.observe(this.element)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.observer?.disconnect()
  }

  used(event) {
    if (event.target.closest("a")) this.remember()
  }

  dismiss() {
    this.remember()
    this.element.remove()
  }

  remember() {
    if (this.remembered) return
    this.remembered = true
    this.observer?.disconnect()
    rememberDismissal(this.keyValue)
  }
}
