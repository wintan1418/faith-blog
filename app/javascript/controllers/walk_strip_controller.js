import { Controller } from "@hotwired/stimulus"

// "Your walk" strip on the phone feed: remembers on this device whether it
// was folded. Storage can be missing (private windows, some WebViews), so
// every read and write is guarded and the strip simply stays open.
const KEY = "brethreign:walk-strip-folded"

export default class extends Controller {
  connect() {
    try {
      if (window.localStorage.getItem(KEY) === "1") this.element.open = false
    } catch { /* storage unavailable: stay open */ }
  }

  remember() {
    try {
      if (this.element.open) window.localStorage.removeItem(KEY)
      else window.localStorage.setItem(KEY, "1")
    } catch { /* ignore */ }
  }
}
