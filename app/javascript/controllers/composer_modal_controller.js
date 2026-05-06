import { Controller } from "@hotwired/stimulus"

// Opens and closes the post composer <dialog>.
// Trigger any element with data-action="click->composer-modal#open"
// somewhere in the DOM; the controller targets the global #composer-dialog.
export default class extends Controller {
  static targets = ["dialog", "body"]

  connect() {
    this.handleSubmitEnd = this.handleSubmitEnd.bind(this)
    document.addEventListener("turbo:submit-end", this.handleSubmitEnd)
  }

  disconnect() {
    document.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
  }

  open(event) {
    if (event) event.preventDefault()
    const dialog = this.dialogTarget
    if (typeof dialog.showModal === "function") {
      dialog.showModal()
    } else {
      dialog.setAttribute("open", "")
    }
    // Defer focus so the trix-editor inside has time to mount.
    requestAnimationFrame(() => {
      const editor = dialog.querySelector("trix-editor")
      if (editor) editor.focus()
    })
  }

  close(event) {
    if (event) event.preventDefault()
    const dialog = this.dialogTarget
    if (typeof dialog.close === "function") {
      dialog.close()
    } else {
      dialog.removeAttribute("open")
    }
  }

  // Close when the user clicks on the backdrop (outside the panel).
  backdropClick(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  handleSubmitEnd(event) {
    if (!this.element.contains(event.target)) return
    if (event.detail.success) {
      this.close()
    }
  }
}
