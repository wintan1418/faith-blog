import { Controller } from "@hotwired/stimulus"

// Toggle a turbo-frame open/closed.
// First click: set src (Turbo loads it) + remove .hidden
// Subsequent clicks: just toggle .hidden so we don't refetch.
export default class extends Controller {
  static values = { url: String, frame: String }

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
}
