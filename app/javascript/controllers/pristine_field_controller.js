import { Controller } from "@hotwired/stimulus"

// Mobile browsers (Samsung Internet, Chrome Android) ignore
// autocomplete=off and refill comment[content] fields with a body
// the user submitted earlier — often the raw Trix HTML wrapper, which
// is what users saw leaking into reply boxes ("<div class=trix-content>…").
//
// This controller pins the field to its intended value — empty for a
// fresh reply form, the comment's plain text for an edit form — and
// re-asserts it across the autofill window (which can land anytime in
// the first ~2s, frequently right after focus). It steps aside the
// instant the user actually types or pastes.
//
// Attach to a <textarea> directly, or to a wrapper/<form> that holds a
// <trix-editor> (the rich-text reply). For Trix, only the empty case
// is enforced — we never want to wipe a real draft.
export default class extends Controller {
  static values = { value: { type: String, default: "" } }

  connect() {
    this.touched = false
    this.markTouched = this.markTouched.bind(this)
    this.onFocus = this.onFocus.bind(this)

    if (this.element.tagName === "TEXTAREA") {
      this.field = this.element
    } else {
      this.field = this.element.querySelector("textarea")
      this.trix  = this.element.querySelector("trix-editor")
    }

    this.watched = [this.field, this.trix].filter(Boolean)
    for (const node of this.watched) {
      node.addEventListener("keydown", this.markTouched)
      node.addEventListener("paste", this.markTouched)
      node.addEventListener("focus", this.onFocus)
    }

    this.enforce()
    this.timers = [40, 120, 300, 600, 1100, 1800].map(ms =>
      setTimeout(() => this.enforce(), ms)
    )
  }

  disconnect() {
    for (const node of this.watched || []) {
      node.removeEventListener("keydown", this.markTouched)
      node.removeEventListener("paste", this.markTouched)
      node.removeEventListener("focus", this.onFocus)
    }
    ;(this.timers || []).forEach(clearTimeout)
  }

  markTouched() {
    this.touched = true
    // Other controllers (emoji picker, mentions) check this flag before
    // they mutate the field, and set it themselves when they do.
    this.field?.setAttribute("data-pristine-touched", "1")
    this.trix?.setAttribute("data-pristine-touched", "1")
  }

  // Autofill commonly fires the moment a field receives focus — give it
  // a couple of beats, then snap the value back if the user hasn't typed.
  onFocus() {
    if (this.released()) return
    setTimeout(() => this.enforce(), 50)
    setTimeout(() => this.enforce(), 250)
  }

  // The field is "released" once the user — or a cooperating controller
  // like the emoji picker — has legitimately put content in it.
  released() {
    if (this.touched) return true
    if (this.field?.dataset.pristineTouched === "1") return true
    if (this.trix?.dataset.pristineTouched === "1") return true
    return false
  }

  enforce() {
    if (this.released()) return

    if (this.field && this.field.value !== this.valueValue) {
      this.field.value = this.valueValue
    }

    if (this.trix && this.trix.editor && this.valueValue === "") {
      const doc = this.trix.editor.getDocument()
      if (doc && doc.toString().trim() !== "") {
        this.trix.editor.loadHTML("")
      }
    }
  }
}
