import { Controller } from "@hotwired/stimulus"

// Seeds rank-up celebration: opens once, and is marked seen the moment it
// shows, so it never comes back (even if the page is left without closing it).
export default class extends Controller {
  static values = { seenUrl: String }

  connect() {
    this.openTimer = setTimeout(() => {
      if (!this.element.isConnected || this.element.open) return
      // One celebration at a time: a second copy (page + stream) stays shut.
      if (document.querySelector("dialog.seed-rankup[open]")) return this.element.remove()
      this.element.showModal()
      this.markSeen()
    }, 500)
  }

  disconnect() {
    clearTimeout(this.openTimer)
  }

  close() {
    this.element.classList.add("is-leaving")
    setTimeout(() => {
      if (this.element.open) this.element.close()
      this.element.remove()
    }, 220)
  }

  markSeen() {
    if (this.marked) return
    this.marked = true
    const token = document.querySelector("meta[name=csrf-token]")?.content || ""
    fetch(this.seenUrlValue, { method: "POST", credentials: "same-origin", keepalive: true, headers: { "X-CSRF-Token": token } })
  }
}
