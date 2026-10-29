import { Controller } from "@hotwired/stimulus"
import { loadEditor } from "../lazy_libs"

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

  async handlePrefill(event) {
    const text = event.detail && event.detail.text
    if (!text) return
    this.open()
    const editor = await this.readyEditor()
    if (!editor) return
    editor.editor.loadHTML("")
    editor.editor.insertString(text)
  }

  // The editor library loads on demand, so wait until the composer's editor
  // is ready before putting text in it (otherwise the text is silently lost).
  async readyEditor() {
    await loadEditor()
    const el = this.dialogTarget.querySelector("trix-editor")
    if (!el) return null
    if (el.editor) return el
    return new Promise((resolve) => {
      const done = () => resolve(el.editor ? el : null)
      el.addEventListener("trix-initialize", done, { once: true })
      setTimeout(done, 3000)
    })
  }

  // Open with starter text from a data-composer-modal-prefill-param — used by
  // the composer chips ("Prayer request", "Share a verse"). Never clobbers a
  // draft: only inserts when the editor is empty.
  async openWith(event) {
    const text = event.params && event.params.prefill
    this.open(event)
    if (!text) return
    const editor = await this.readyEditor()
    if (editor && editor.editor.getDocument().toString().trim() === "") editor.editor.insertString(text)
  }

  open(event) {
    if (event) event.preventDefault()
    loadEditor()
    const dialog = this.dialogTarget
    if (typeof dialog.showModal === "function") {
      dialog.open || dialog.showModal()
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
