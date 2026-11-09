import { Controller } from "@hotwired/stimulus"
import { loadEmojiPicker } from "../lazy_libs"

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
    this.releaseRoom()
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
    loadEmojiPicker()
    if (this.hasPickerTarget) {
      this.pickerTarget.classList.remove("hidden")
      this.pickerVisible = true
      requestAnimationFrame(() => this.keepFieldVisible())
      
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
      this.releaseRoom()
      if (this.boundCloseOnOutside) {
        document.removeEventListener("click", this.boundCloseOnOutside)
      }
    }
  }

  // On phones the picker is a sheet pinned to the bottom of the screen, which
  // can sit right on top of a reply box. Scroll the box up so it shows just
  // above the sheet (adding room at the end of the page if it's needed), so
  // you can see each emoji land.
  keepFieldVisible() {
    if (!this.hasPickerTarget || getComputedStyle(this.pickerTarget).position !== "fixed") return
    const field = this.field()
    if (!field) return
    const sheetTop = this.pickerTarget.getBoundingClientRect().top
    const overlap = field.getBoundingClientRect().bottom + 12 - sheetTop
    if (overlap <= 0) return

    const room = Math.ceil(window.innerHeight - sheetTop)
    this.addedRoom = room
    document.body.style.paddingBottom = `${room}px`
    window.scrollBy({ top: overlap, behavior: "smooth" })
  }

  releaseRoom() {
    if (!this.addedRoom) return
    document.body.style.paddingBottom = ""
    this.addedRoom = null
  }

  field() {
    const form = this.element.closest("form") || this.element
    return (this.hasEditorTarget && this.editorTarget) ||
      form.querySelector("trix-editor, textarea")
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
      if (!this.touchScreen()) trixEditor.focus()
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
        if (!this.touchScreen()) textarea.focus()
        textarea.dispatchEvent(new Event("input", { bubbles: true }))
      }
    }
    // Stay open so several emoji can go in; the button or a tap outside closes it.
  }

  // On a phone, focusing the box after each emoji pops the keyboard up over
  // the picker. Leave focus alone there; the text still lands at the caret.
  touchScreen() {
    return window.matchMedia("(pointer: coarse)").matches
  }
}
