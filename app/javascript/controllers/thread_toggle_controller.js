import { Controller } from "@hotwired/stimulus"

// Open / close a turbo-frame thread, AND keep the count label on the
// trigger button in sync when the user posts a reply inside the
// frame — so the user doesn't have to refresh to see the new count.
export default class extends Controller {
  static values  = { url: String, frame: String }
  static targets = ["count"]

  connect() {
    this.boundSubmitEnd = this.handleSubmitEnd.bind(this)
    document.addEventListener("turbo:submit-end", this.boundSubmitEnd)
  }

  disconnect() {
    document.removeEventListener("turbo:submit-end", this.boundSubmitEnd)
  }

  toggle(event) {
    event.preventDefault()
    const frame = document.getElementById(this.frameValue)
    if (!frame) return

    const isClosed = frame.classList.contains("is-closed") || frame.children.length === 0

    if (isClosed) {
      if (!frame.src && frame.children.length === 0) {
        frame.src = this.urlValue
      }
      frame.classList.remove("is-closed")
    } else {
      frame.classList.add("is-closed")
    }
  }

  // When a form inside this thread's frame submits successfully, bump
  // the local count by 1. Saves a round-trip and matches what the
  // server already wrote (counter_cache fired on Comment create).
  handleSubmitEnd(event) {
    if (!event.detail || !event.detail.success) return
    const form = event.target
    if (!form) return
    if (form.dataset.turboFrame !== this.frameValue) return

    this.bumpCount()
  }

  bumpCount() {
    const button = this.element
    const span = button.querySelector("span")
    if (!span) return

    // If we already have "Open thread · N voices", increment N.
    const current = parseInt(span.dataset.count || "0", 10)
    const next = (Number.isFinite(current) ? current : 0) + 1

    span.dataset.count = String(next)
    span.textContent = `Open thread · ${next} ${next === 1 ? "voice" : "voices"}`

    // Make sure the parent card now reads as a thread visually.
    button.classList.add("is-thread")
  }
}
