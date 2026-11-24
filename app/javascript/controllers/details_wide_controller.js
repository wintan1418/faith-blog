import { Controller } from "@hotwired/stimulus"

// A <details> that starts open on wide screens and folded on phones (the
// series card's list of parts). The reader can still open or close it.
export default class extends Controller {
  static values = { minWidth: { type: Number, default: 768 } }

  connect() {
    if (window.matchMedia(`(min-width: ${this.minWidthValue}px)`).matches) this.element.open = true
  }
}
