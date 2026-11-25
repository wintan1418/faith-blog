import { Controller } from "@hotwired/stimulus"

// A chapter page counts as read after a minute on it, counted only while the
// page is actually on screen (tab visible). Posts once, then the server's
// Turbo Stream redraws the Daily Bible bars.
export default class extends Controller {
  static values = { url: String, chapter: String, seconds: { type: Number, default: 60 } }

  connect() {
    this.elapsed = 0
    this.sent = false
    this.tick = this.tick.bind(this)
    this.timer = setInterval(this.tick, 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    if (this.sent || document.visibilityState !== "visible") return
    this.elapsed += 1
    if (this.elapsed >= this.secondsValue) this.send()
  }

  async send() {
    this.sent = true
    clearInterval(this.timer)
    const token = document.querySelector("meta[name=csrf-token]")?.content || ""
    const body = new FormData()
    body.set("source", "dwell")
    body.set("chapter", this.chapterValue)
    try {
      const response = await fetch(this.urlValue, {
        method: "POST", body, credentials: "same-origin",
        headers: { "X-CSRF-Token": token, "Accept": "text/vnd.turbo-stream.html" }
      })
      if (!response.ok) return
      const text = await response.text()
      if ((response.headers.get("content-type") || "").includes("turbo-stream") && window.Turbo) {
        window.Turbo.renderStreamMessage(text)
      }
    } catch (_) {
      // Offline or the page went away: nothing to do, the buttons still work.
    }
  }
}
