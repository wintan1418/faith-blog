import { Controller } from "@hotwired/stimulus"

// Opens and closes the post composer <dialog>.
// Trigger any element with data-action="click->composer-modal#open"
// somewhere in the DOM; the controller targets the global #composer-dialog.
export default class extends Controller {
  static targets = ["dialog", "body"]

  connect() {
    this.handleSubmitEnd = this.handleSubmitEnd.bind(this)
    this.handlePrefill = this.handlePrefill.bind(this)
    document.addEventListener("turbo:submit-end", this.handleSubmitEnd)
    document.addEventListener("composer:prefill", this.handlePrefill)
  }

  disconnect() {
    document.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
    document.removeEventListener("composer:prefill", this.handlePrefill)
  }

  handlePrefill(event) {
    const text = event.detail && event.detail.text
    if (!text) return
    this.open()
    // Two frames so the dialog is open and trix is mounted before we touch it.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const editor = this.dialogTarget.querySelector("trix-editor")
      if (editor && editor.editor) {
        editor.editor.loadHTML("")
        editor.editor.insertString(text)
      }
    }))
  }

  // Open with starter text from a data-composer-modal-prefill-param — used by
  // the composer chips ("Prayer request", "Share a verse"). Never clobbers a
  // draft: only inserts when the editor is empty.
  openWith(event) {
    const text = event.params && event.params.prefill
    this.open(event)
    if (!text) return
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const editor = this.dialogTarget.querySelector("trix-editor")
      if (editor && editor.editor && editor.editor.getDocument().toString().trim() === "") {
        editor.editor.insertString(text)
      }
    }))
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
