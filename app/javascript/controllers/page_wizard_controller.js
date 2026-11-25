import { Controller } from "@hotwired/stimulus"

// "Create a page" in a few short steps (one form, shown a step at a time).
// Without JavaScript every step shows at once and the form still works.
// The address is suggested from the name and checked as you type.
export default class extends Controller {
  static targets = ["step", "dot", "next", "back", "submit", "name", "handle", "handleStatus"]
  static values = { checkUrl: String, start: { type: Number, default: 0 } }

  connect() {
    this.element.classList.add("is-wizard")
    this.handleEdited = this.hasHandleTarget && this.handleTarget.value.length > 0
    this.show(this.startValue)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.request?.abort()
  }

  next() {
    const step = this.stepTargets[this.index]
    // The browser's own checks for the fields on this step (required, pattern…).
    const invalid = [...step.querySelectorAll("input, select, textarea")].find((field) => !field.checkValidity())
    if (invalid) {
      invalid.reportValidity()
      return
    }
    if (this.index === 1 && this.handleTaken) {
      this.handleTarget.focus()
      return
    }
    this.show(this.index + 1)
  }

  back() {
    this.show(this.index - 1)
  }

  show(index) {
    this.index = Math.max(0, Math.min(index, this.stepTargets.length - 1))
    this.stepTargets.forEach((step, i) => { step.hidden = i !== this.index })
    this.dotTargets.forEach((dot, i) => {
      dot.classList.toggle("is-active", i === this.index)
      dot.classList.toggle("is-done", i < this.index)
      if (i === this.index) dot.setAttribute("aria-current", "step")
      else dot.removeAttribute("aria-current")
    })
    const last = this.index === this.stepTargets.length - 1
    this.backTarget.hidden = this.index === 0
    this.nextTarget.hidden = last
    this.submitTarget.hidden = !last
    if (this.index === 1 && !this.handleEdited) this.suggestHandle()
    const first = this.stepTargets[this.index].querySelector("input:not([type=hidden]):not([type=radio]):not([type=file]), textarea")
    if (first && this.started) first.focus({ preventScroll: true })
    if (this.started) this.element.scrollIntoView({ block: "start", behavior: "smooth" })
    this.started = true
  }

  nameChanged() {
    if (!this.handleEdited) this.handleTarget.value = ""
  }

  handleChanged() {
    this.handleEdited = true
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.check(), 250)
  }

  suggestHandle() {
    const base = (this.nameTarget.value || "")
      .normalize("NFKD").replace(/[^\x00-\x7F]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "").slice(0, 26)
    if (base.length < 3) return
    this.check(base, true)
  }

  async check(handle = this.handleTarget.value.trim(), suggesting = false) {
    if (!this.checkUrlValue || handle.length === 0) return
    this.request?.abort()
    this.request = new AbortController()
    const url = new URL(this.checkUrlValue, window.location.origin)
    url.searchParams.set("handle", handle)
    if (suggesting) url.searchParams.set("name", this.nameTarget.value)
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: this.request.signal })
      if (!response.ok) return
      const data = await response.json()
      if (suggesting) {
        this.handleTarget.value = data.available ? data.handle : (data.suggestion || "")
        this.handleTaken = false
        this.status(`brethreign.com/p/${this.handleTarget.value} is free.`, false)
      } else {
        this.handleTaken = !data.available
        this.status(data.available ? `@${data.handle} is free.` : data.message, !data.available)
      }
    } catch (error) {
      if (error.name !== "AbortError") this.status("", false)
    }
  }

  status(text, bad) {
    if (!this.hasHandleStatusTarget) return
    this.handleStatusTarget.textContent = text
    this.handleStatusTarget.classList.toggle("is-bad", bad)
    this.handleStatusTarget.classList.toggle("is-good", !bad && text.length > 0)
  }
}
