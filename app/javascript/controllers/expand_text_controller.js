import { Controller } from "@hotwired/stimulus"

// LinkedIn-style "…more" expander. The full content is always in the DOM;
// CSS clamps only breaths marked .is-clamped (long ones). If a "long" breath
// actually fits once rendered, show it whole: no fade, no "…more".
export default class extends Controller {
  static targets = ["copy", "toggle"]

  connect() {
    if (!this.hasCopyTarget || !this.copyTarget.classList.contains("is-clamped")) return
    requestAnimationFrame(() => {
      const el = this.copyTarget
      if (el.scrollHeight <= el.clientHeight + 2) this.showAll()
    })
  }

  expand(event) {
    event.preventDefault()
    event.stopPropagation()
    this.showAll()
  }

  showAll() {
    if (this.hasCopyTarget) this.copyTarget.classList.add("is-expanded")
    if (this.hasToggleTarget) this.toggleTarget.remove()
  }
}
