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
    // On /posts/new the composer is the page itself, not the pop-up: Cancel
    // leaves the page instead (it used to do nothing there).
    const button = event?.currentTarget
    if (button instanceof Element && !this.dialogTarget.contains(button)) return this.leavePage()
    const dialog = this.dialogTarget
    if (typeof dialog.close === "function") {
      dialog.close()
    } else {
      dialog.removeAttribute("open")
    }
  }

  // Back to where they came from. In the apps, close the screen (Hotwire
  // Native pops it); on the web, go back, or to the feed for a direct link.
  leavePage() {
    if (document.body.classList.contains("hotwire-native")) {
      window.Turbo?.visit("/recede_historical_location")
    } else if (history.length > 1 && document.referrer.startsWith(location.origin)) {
      history.back()
    } else {
      window.Turbo ? window.Turbo.visit("/feed", { action: "replace" }) : (location.href = "/feed")
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
    this.clearSendError()
    if (event.detail.success) {
      this.close()
    } else if (!event.detail.fetchResponse) {
      // Nothing came back: the upload never left the phone or the connection
      // dropped. Say so, instead of a button that seems to do nothing.
      this.showSendError(event.target)
    }
  }

  showSendError(form) {
    const note = document.createElement("p")
    note.className = "fc-composer-send-error"
    note.setAttribute("role", "alert")
    note.textContent = "Your post didn't send. Check your connection and tap the button again. " +
      "If you added a photo, remove it and choose it again. Your words are still here."
    const actions = form.querySelector("[type=submit]")?.parentElement
    actions ? actions.before(note) : form.prepend(note)
  }

  clearSendError() {
    this.element.querySelectorAll(".fc-composer-send-error").forEach(n => n.remove())
  }
}
