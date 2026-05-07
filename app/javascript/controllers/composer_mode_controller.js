import { Controller } from "@hotwired/stimulus"

// Toggles the composer between Breathe and Thread modes:
//   - swaps hidden kind field
//   - swaps title / body placeholders
//   - swaps the submit label
//   - swaps the author handle copy
//   - moves the .is-active state on the tabs
export default class extends Controller {
  static targets = ["tab", "kindField", "title", "body", "submit", "handle"]
  static values  = { initial: { type: String, default: "breath" } }

  connect() {
    this.apply(this.initialValue)
  }

  switch(event) {
    event.preventDefault()
    const mode = event.currentTarget.dataset.mode
    if (!mode) return
    this.apply(mode)
  }

  apply(mode) {
    if (this.hasKindFieldTarget) this.kindFieldTarget.value = mode

    if (this.hasTitleTarget) {
      const placeholder = this.titleTarget.dataset[`title${this.cap(mode)}`]
      if (placeholder) this.titleTarget.placeholder = placeholder
      // Title is required only for threads — breaths can post without one.
      this.titleTarget.required = mode === "thread"
    }

    if (this.hasBodyTarget) {
      const placeholder = this.bodyTarget.dataset[`body${this.cap(mode)}`]
      if (placeholder) {
        // Trix reads from the underlying <input>, but the placeholder is on the
        // trix-editor element next to it. Keep both in sync.
        this.bodyTarget.placeholder = placeholder
        const editor = this.element.querySelector("trix-editor")
        if (editor) editor.setAttribute("placeholder", placeholder)
      }
    }

    if (this.hasSubmitTarget) {
      const label = this.submitTarget.dataset[`submit${this.cap(mode)}`]
      if (label) {
        // Works for both <input type=submit> (legacy, uses .value) and
        // <button type=submit> (current, uses textContent).
        if (this.submitTarget.tagName === "BUTTON") {
          this.submitTarget.textContent = label
        } else {
          this.submitTarget.value = label
        }
      }
    }

    if (this.hasHandleTarget) {
      const copy = this.handleTarget.dataset[`handle${this.cap(mode)}`]
      if (copy) this.handleTarget.textContent = copy
    }

    if (this.hasTabTarget) {
      this.tabTargets.forEach(t => t.classList.toggle("is-active", t.dataset.mode === mode))
    }
  }

  cap(s) { return s.charAt(0).toUpperCase() + s.slice(1) }
}
