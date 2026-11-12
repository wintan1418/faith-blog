import { Controller } from "@hotwired/stimulus"

// Keeps what you're typing above a sticky bar at the bottom of a scrolling form.
//
// On phones the breath composer is a full-screen sheet whose Cancel / Save draft /
// Breathe bar sticks to the bottom of the scrolling form. With the keyboard up the
// browser only scrolls the caret to the bottom edge of the form — which is right
// behind that bar — so each new line was typed out of sight ("I type and nothing
// shows"), and on short screens the whole editor sat under the bar.
//
// After every edit, caret move or viewport resize (the keyboard opening), scroll
// the form just enough that the caret clears the bar.
export default class extends Controller {
  static targets = ["bar"]

  connect() {
    this.schedule = () => {
      cancelAnimationFrame(this.frame)
      this.frame = requestAnimationFrame(() => this.reveal())
    }
    this.events = ["input", "focusin", "keyup", "click", "trix-selection-change"]
    this.events.forEach((name) => this.element.addEventListener(name, this.schedule))
    window.visualViewport?.addEventListener("resize", this.schedule)
  }

  disconnect() {
    this.events.forEach((name) => this.element.removeEventListener(name, this.schedule))
    window.visualViewport?.removeEventListener("resize", this.schedule)
    cancelAnimationFrame(this.frame)
  }

  reveal() {
    if (!this.hasBarTarget || getComputedStyle(this.barTarget).position !== "sticky") return
    const caret = this.caretRect()
    if (!caret) return

    const barTop = this.barTarget.getBoundingClientRect().top
    const overlap = caret.bottom + 12 - barTop
    if (overlap > 0) this.element.scrollTop += overlap
  }

  // Where the caret is on screen, for the field being typed in inside this form.
  caretRect() {
    const field = document.activeElement
    if (!field || !this.element.contains(field) || field === this.element) return null

    // Rich text (Trix): it can measure its own caret, even on an empty line.
    if (field.editor?.getClientRectAtPosition) {
      const [ position ] = field.editor.getSelectedRange() || []
      const rect = position == null ? null : field.editor.getClientRectAtPosition(position)
      if (rect && rect.height) return rect
    }

    if (field.isContentEditable) {
      const selection = window.getSelection()
      if (selection?.rangeCount) {
        const range = selection.getRangeAt(0).cloneRange()
        range.collapse(false)
        const rect = range.getClientRects()[0] || range.getBoundingClientRect()
        if (rect && rect.height) return rect
      }
    }

    // A text box: keep its last visible line in view (it scrolls inside itself).
    const box = field.getBoundingClientRect()
    if (!box.height) return null
    const line = parseFloat(getComputedStyle(field).lineHeight) || 24
    return { top: box.top, bottom: Math.min(box.bottom, box.top + line * 2) }
  }
}
