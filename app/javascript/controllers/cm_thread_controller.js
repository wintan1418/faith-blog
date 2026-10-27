import { Controller } from "@hotwired/stimulus"

// A comment's reply chain: "View earlier replies" (or the "N replies" count)
// unfolds the older replies that start folded away.
export default class extends Controller {
  static targets = ["older", "more"]

  expand() {
    this.olderTargets.forEach(el => el.classList.remove("hidden"))
    this.moreTargets.forEach(el => el.remove())
  }
}
