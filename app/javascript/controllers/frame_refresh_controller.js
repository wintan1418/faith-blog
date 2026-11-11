import { Controller } from "@hotwired/stimulus"

// Reloads a <turbo-frame> from `url` every `interval` seconds, only while the
// page is visible, and straight away when the page becomes visible again.
// Used for the feed's "Online now" row and Admin → Online now.
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 30 } }

  connect() {
    this.onVisibility = this.onVisibility.bind(this)
    document.addEventListener("visibilitychange", this.onVisibility)
    this.start()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.stop()
  }

  onVisibility() {
    if (document.visibilityState === "visible") {
      this.refresh()
      this.start()
    } else {
      this.stop()
    }
  }

  start() {
    this.stop()
    if (document.visibilityState !== "visible") return
    this.timer = setInterval(() => this.refresh(), this.intervalValue * 1000)
  }

  stop() {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
  }

  refresh() {
    if (document.visibilityState !== "visible" || !this.urlValue) return

    // The first render is inline; setting src makes Turbo fetch it, later beats reload.
    if (this.element.getAttribute("src")) {
      this.element.reload()
    } else {
      this.element.src = this.urlValue
    }
  }
}
