import { Controller } from "@hotwired/stimulus"

// Watches a hidden bucket that turbo-stream prepends arrival markers into.
// When the bucket is non-empty, surfaces a sticky pill that, when clicked,
// scrolls to top and reloads the feed so the user sees the new breaths.
export default class extends Controller {
  static targets = ["bucket", "pill", "count", "label"]

  connect() {
    if (!this.hasBucketTarget) return
    this.observer = new MutationObserver(() => this.refresh())
    this.observer.observe(this.bucketTarget, { childList: true })
    this.refresh()
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  refresh() {
    const n = this.bucketTarget.childElementCount
    if (this.hasCountTarget) this.countTarget.textContent = n
    if (this.hasLabelTarget) this.labelTarget.textContent = n === 1 ? "new breath" : "new breaths"
    if (this.hasPillTarget) this.pillTarget.classList.toggle("hidden", n === 0)
  }

  flush(event) {
    event.preventDefault()
    window.scrollTo({ top: 0, behavior: "smooth" })
    setTimeout(() => window.location.reload(), 280)
  }
}
