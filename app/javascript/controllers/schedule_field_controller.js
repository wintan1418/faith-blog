import { Controller } from "@hotwired/stimulus"

// The composer's Schedule picker. The picker works in the phone's own time;
// the hidden field sends that moment with its time zone (ISO 8601), so a
// breath set for 9:00 PM in Lagos goes out at 9:00 PM in Lagos.
// With a future time picked, the main button reads "Schedule".
export default class extends Controller {
  static targets = ["local", "utc", "clear", "note"]
  static values = { utc: String }

  connect() {
    this.localTarget.min = this.toLocalInput(new Date())
    if (this.utcValue) this.localTarget.value = this.toLocalInput(new Date(this.utcValue))
    this.sync()
  }

  sync() {
    const raw = this.localTarget.value
    const when = raw ? new Date(raw) : null // "YYYY-MM-DDTHH:MM" is read as local time
    const future = when && !isNaN(when) && when.getTime() > Date.now() + 30_000
    this.utcTarget.value = when && !isNaN(when) ? when.toISOString() : ""
    this.clearTarget.classList.toggle("hidden", !raw)
    this.setNote(raw && !future ? "Pick a time in the future." : future ? `Goes live ${this.describe(when)}.` : "")
    this.setButton(future)
  }

  clear(event) {
    event.preventDefault()
    this.localTarget.value = ""
    this.sync()
  }

  setButton(scheduled) {
    const button = this.element.closest("form")?.querySelector('[data-composer-mode-target="submit"]')
    if (!button || button.value === "draft") return
    if (scheduled) {
      if (!button.dataset.unscheduledLabel) button.dataset.unscheduledLabel = button.textContent.trim()
      button.textContent = "Schedule"
    } else if (button.dataset.unscheduledLabel) {
      button.textContent = button.dataset.unscheduledLabel
      delete button.dataset.unscheduledLabel
    }
  }

  setNote(text) {
    if (!this.hasNoteTarget) return
    this.noteTarget.textContent = text
    this.noteTarget.classList.toggle("hidden", !text)
  }

  describe(date) {
    return date.toLocaleString(undefined, { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
  }

  toLocalInput(date) {
    const pad = (n) => String(n).padStart(2, "0")
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
  }
}
