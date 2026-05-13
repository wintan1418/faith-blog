import { Controller } from "@hotwired/stimulus"

// Inline edit toggle for a comment. Hides the display block, reveals
// the edit form (PATCH /posts/:id/comments/:id), focuses the textarea.
// Cancel restores the display without sending a request.
export default class extends Controller {
  static targets = ["display", "form", "textarea"]

  edit(event) {
    event?.preventDefault()
    event?.stopPropagation()
    this.displayTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    if (this.hasTextareaTarget) {
      const t = this.textareaTarget
      setTimeout(() => {
        t.focus()
        const len = t.value.length
        t.setSelectionRange(len, len)
      }, 50)
    }
  }

  cancel(event) {
    event?.preventDefault()
    event?.stopPropagation()
    this.formTarget.classList.add("hidden")
    this.displayTarget.classList.remove("hidden")
  }
}
