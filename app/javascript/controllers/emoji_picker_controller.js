import { Controller } from "@hotwired/stimulus"
import "emoji-picker-element"

export default class extends Controller {
  static targets = ["button", "picker", "editor"]

  connect() {
    this.pickerVisible = false
    this.setupPicker()
  }

  setupPicker() {
    if (this.hasPickerTarget) {
      // Configure emoji picker. Keep a bound reference so disconnect() can
      // remove it — otherwise the listener (and the picker element) leaks on
      // every Turbo navigation.
      this.boundInsertEmoji = (event) => this.insertEmoji(event.detail.unicode)
      this.pickerTarget.addEventListener("emoji-click", this.boundInsertEmoji)
    }
  }

  disconnect() {
    if (this.hasPickerTarget && this.boundInsertEmoji) {
      this.pickerTarget.removeEventListener("emoji-click", this.boundInsertEmoji)
    }
    if (this.boundCloseOnOutside) {
      document.removeEventListener("click", this.boundCloseOnOutside)
    }
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    
    if (this.pickerVisible) {
      this.hide()
    } else {
      this.show()
    }
  }

  show() {
    if (this.hasPickerTarget) {
      this.pickerTarget.classList.remove("hidden")
      this.pickerVisible = true
      
      // Close on outside click
      setTimeout(() => {
        document.addEventListener("click", this.boundCloseOnOutside = this.closeOnOutside.bind(this))
      }, 100)
    }
  }

  hide() {
    if (this.hasPickerTarget) {
      this.pickerTarget.classList.add("hidden")
      this.pickerVisible = false
      if (this.boundCloseOnOutside) {
        document.removeEventListener("click", this.boundCloseOnOutside)
      }
    }
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hide()
    }
  }

  insertEmoji(emoji) {
    // Trix editor — only when the target actually is a trix-editor.
    const trixEditor = this.element.closest("form")?.querySelector("trix-editor")

    if (trixEditor && trixEditor.editor) {
      trixEditor.editor.insertString(emoji + " ")
      trixEditor.focus()
      // Tell pristine-field this content is intentional — don't wipe it.
      trixEditor.setAttribute("data-pristine-touched", "1")
    } else {
      // Regular textarea (the reply boxes).
      const textarea = this.hasEditorTarget && this.editorTarget.tagName === "TEXTAREA"
        ? this.editorTarget
        : this.element.closest("form")?.querySelector("textarea")
      if (textarea) {
        const start = textarea.selectionStart ?? textarea.value.length
        const end = textarea.selectionEnd ?? textarea.value.length
        const text = textarea.value
        textarea.value = text.substring(0, start) + emoji + " " + text.substring(end)
        textarea.selectionStart = textarea.selectionEnd = start + emoji.length + 1
        textarea.setAttribute("data-pristine-touched", "1")
        textarea.focus()
        textarea.dispatchEvent(new Event("input", { bubbles: true }))
      }
    }

    this.hide()
  }
}
