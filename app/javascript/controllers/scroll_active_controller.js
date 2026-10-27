import { Controller } from "@hotwired/stimulus"

// A swipeable row of tabs: bring the active one into view on load.
export default class extends Controller {
  connect() {
    const active = this.element.querySelector(".is-active")
    if (active && this.element.scrollWidth > this.element.clientWidth) {
      this.element.scrollLeft = active.offsetLeft - (this.element.clientWidth - active.offsetWidth) / 2
    }
  }
}
