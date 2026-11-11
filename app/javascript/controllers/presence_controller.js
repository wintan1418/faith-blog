import { Controller } from "@hotwired/stimulus"

// Heartbeat for "who's online". While the page is visible, tells the server
// this member is here every ~45s (and right away when they come back to the
// tab or app). Stops while hidden, so a backgrounded tab or app goes offline
// within User::ONLINE_WINDOW. Lives on a turbo-permanent element in the
// signed-in layout, so it keeps one timer across Turbo navigations — and the
// same JS runs inside the Hotwire Native apps' WebView.
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 45 } }

  connect() {
    this.onVisibility = this.onVisibility.bind(this)
    document.addEventListener("visibilitychange", this.onVisibility)
    // The page load itself already marked us as seen; just start the beat.
    if (this.visible) this.start()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.stop()
  }

  get visible() {
    return document.visibilityState === "visible"
  }

  onVisibility() {
    if (this.visible) {
      this.ping()
      this.start()
    } else {
      this.stop()
    }
  }

  start() {
    this.stop()
    this.timer = setInterval(() => this.ping(), this.intervalValue * 1000)
  }

  stop() {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
  }

  ping() {
    if (!this.visible || !this.urlValue) return

    const token = document.querySelector('meta[name="csrf-token"]')?.content || ""
    fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": token, "Accept": "text/plain" },
      credentials: "same-origin",
      keepalive: true
    }).then((response) => {
      // Signed out elsewhere: no point beating on.
      if (response.status === 401) this.stop()
    }).catch(() => {})
  }
}
