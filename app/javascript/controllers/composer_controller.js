import { Controller } from "@hotwired/stimulus"

// Collapsed-first comment composer.
// Click the placeholder row → expanded form appears, focus jumps in.
// Cancel → collapse back.
export default class extends Controller {
  static targets = ["collapsed", "expanded"]

  expand(event) {
    if (event) event.preventDefault()
    if (this.hasCollapsedTarget) this.collapsedTarget.classList.add("hidden")
    if (this.hasExpandedTarget) this.expandedTarget.classList.remove("hidden")
    requestAnimationFrame(() => {
      const editor = this.element.querySelector("trix-editor")
      if (editor) editor.focus()
    })
  }

  collapse(event) {
    if (event) event.preventDefault()
    if (this.hasExpandedTarget) this.expandedTarget.classList.add("hidden")
    if (this.hasCollapsedTarget) this.collapsedTarget.classList.remove("hidden")
  }
}
