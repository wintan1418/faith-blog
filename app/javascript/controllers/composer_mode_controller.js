import { Controller } from "@hotwired/stimulus"

// The composer's "What are you posting?" switch: Breath / Prayer / Verse /
// Thread. A thread is its own kind; a prayer is a breath marked as a prayer
// request; a verse is a breath that starts from scripture. Switching:
//   - sets the hidden kind and prayer_status fields
//   - swaps title / body placeholders (title is required only for threads)
//   - swaps the submit label
//   - moves the checked state on the segmented control
// Other parts of the page can switch it with a `composer:mode` event
// ({ detail: { mode: "prayer" } }) dispatched on document.
const MODES = [ "breath", "prayer", "verse", "thread" ]

export default class extends Controller {
  static targets = [ "tab", "kindField", "prayerField", "title", "titleLabel", "body", "submit", "handle", "formatBtn" ]
  static values  = { initial: { type: String, default: "breath" } }

  connect() {
    this.onModeEvent = (event) => {
      const mode = event.detail && event.detail.mode
      if (MODES.includes(mode) && this.element.closest("dialog")) this.apply(mode)
    }
    document.addEventListener("composer:mode", this.onModeEvent)
    this.apply(this.initialValue)
  }

  disconnect() {
    document.removeEventListener("composer:mode", this.onModeEvent)
  }

  switch(event) {
    event.preventDefault()
    const mode = event.currentTarget.dataset.mode
    if (!mode) return
    this.apply(mode)
  }

  // The bold / list / quote buttons stay tucked away until asked for, so the
  // writing area isn't crowded.
  toggleFormatting(event) {
    event.preventDefault()
    const on = !this.element.classList.contains("show-format")
    this.element.classList.toggle("show-format", on)
    if (this.hasFormatBtnTarget) this.formatBtnTarget.setAttribute("aria-pressed", on ? "true" : "false")
    const editor = this.element.querySelector("trix-editor")
    if (on && editor) editor.focus()
  }

  // Arrow keys move through the segmented control like a radio group.
  arrow(event) {
    const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key]
    if (!step || !this.hasTabTarget) return
    event.preventDefault()
    const tabs = this.tabTargets
    const current = tabs.findIndex(t => t.getAttribute("aria-checked") === "true")
    const next = tabs[(current + step + tabs.length) % tabs.length]
    this.apply(next.dataset.mode)
    next.focus()
  }

  apply(mode) {
    if (!MODES.includes(mode)) mode = "breath"
    this.mode = mode
    const key = this.cap(mode)

    if (this.hasKindFieldTarget) this.kindFieldTarget.value = mode === "thread" ? "thread" : "breath"

    if (this.hasPrayerFieldTarget) {
      const on = this.prayerFieldTarget.dataset.prayerOn || "prayer_pending"
      this.prayerFieldTarget.value = mode === "prayer" ? on : "not_a_prayer"
    }

    if (this.hasTitleTarget) {
      const placeholder = this.titleTarget.dataset[`title${key}`]
      if (placeholder) this.titleTarget.placeholder = placeholder
      // Title is required only for threads — breaths can post without one.
      this.titleTarget.required = mode === "thread"
      this.element.classList.toggle("is-thread", mode === "thread")
    }
    if (this.hasTitleLabelTarget) {
      this.titleLabelTarget.textContent = mode === "thread" ? "Thread question" : "Title (optional)"
    }

    if (this.hasBodyTarget) {
      const placeholder = this.bodyTarget.dataset[`body${key}`]
      if (placeholder) {
        // Trix reads from the underlying <input>, but the placeholder is on the
        // trix-editor element next to it. Keep both in sync.
        this.bodyTarget.placeholder = placeholder
        const editor = this.element.querySelector("trix-editor")
        if (editor) editor.setAttribute("placeholder", placeholder)
      }
    }

    if (this.hasSubmitTarget) {
      const label = this.submitTarget.dataset[`submit${key}`]
      if (label) {
        if (this.submitTarget.tagName !== "BUTTON") {
          this.submitTarget.value = label
        } else if (this.submitTarget.dataset.unscheduledLabel) {
          // A time is picked: the button says "Schedule"; restore to this later.
          this.submitTarget.dataset.unscheduledLabel = label
        } else {
          const span = this.submitTarget.querySelector("[data-label]")
          if (span) span.textContent = label
          else this.submitTarget.textContent = label
        }
      }
    }

    if (this.hasHandleTarget) {
      const copy = this.handleTarget.dataset[`handle${key}`]
      if (copy) this.handleTarget.textContent = copy
    }

    if (this.hasTabTarget) {
      this.tabTargets.forEach(t => {
        const on = t.dataset.mode === mode
        t.classList.toggle("is-active", on)
        if (t.getAttribute("role") === "radio") {
          t.setAttribute("aria-checked", on ? "true" : "false")
          t.tabIndex = on ? 0 : -1
        }
      })
    }
  }

  cap(s) { return s.charAt(0).toUpperCase() + s.slice(1) }
}
