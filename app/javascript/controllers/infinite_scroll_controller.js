import { Controller } from "@hotwired/stimulus"

// Sentinel that auto-loads the next page of the feed when it scrolls near
// the viewport. Server returns a turbo_stream that appends new cards and
// replaces this sentinel with the next-page one (or removes it when done).
export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!this.urlValue) return
    this.io = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) this.load()
    }, { rootMargin: "300px 0px" })
    this.io.observe(this.element)
  }

  disconnect() {
    if (this.io) this.io.disconnect()
  }

  async load() {
    if (this.loading) return
    this.loading = true
    try {
      const response = await fetch(this.urlValue, {
        headers: { "Accept": "text/vnd.turbo-stream.html" }
      })
      if (!response.ok) return
      const text = await response.text()
      // window.Turbo is exposed by @hotwired/turbo-rails on load.
      if (window.Turbo && typeof window.Turbo.renderStreamMessage === "function") {
        window.Turbo.renderStreamMessage(text)
      }
    } catch (e) {
      // Silently fail — the sentinel stays and will retry if it re-enters view.
    } finally {
      this.loading = false
    }
  }
}
