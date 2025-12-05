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
      // Configure emoji picker
      this.pickerTarget.addEventListener("emoji-click", (event) => {
        this.insertEmoji(event.detail.unicode)
      })
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
    // Find Trix editor
    const trixEditor = this.hasEditorTarget ? this.editorTarget : 
      this.element.closest("form")?.querySelector("trix-editor")
    
    if (trixEditor && trixEditor.editor) {
      trixEditor.editor.insertString(emoji + " ")
      trixEditor.focus()
    } else {
      // Fallback for regular textarea
      const textarea = this.element.closest("form")?.querySelector("textarea")
      if (textarea) {
        const start = textarea.selectionStart
        const end = textarea.selectionEnd
        const text = textarea.value
        textarea.value = text.substring(0, start) + emoji + " " + text.substring(end)
        textarea.selectionStart = textarea.selectionEnd = start + emoji.length + 1
        textarea.focus()
      }
    }
    
    this.hide()
  }
}
