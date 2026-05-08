import { Controller } from "@hotwired/stimulus"

// LinkedIn-style "…more" expander. The full content is always in the DOM;
// CSS clamps the visible height. Click removes the clamp class and the
// button. No display:none, no duplicate nodes, no nesting traps.
export default class extends Controller {
  static targets = ["copy", "toggle"]

  expand(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this.hasCopyTarget) this.copyTarget.classList.add("is-expanded")
    if (this.hasToggleTarget) this.toggleTarget.remove()
  }
}
