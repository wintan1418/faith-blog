import { Controller } from "@hotwired/stimulus"

// The on/off switch for the background scripture rain (Settings → Accent and
// the account menu). Flips the rain at once, then saves it on the account.
export default class extends Controller {
  static targets = ["label"]
  static values = { url: String }

  connect() {
    this.onSet = (e) => this.render(!!e.detail?.on)
    window.addEventListener("rain:set", this.onSet)
    this.render(this.isOn())
  }

  disconnect() {
    window.removeEventListener("rain:set", this.onSet)
  }

  isOn() {
    return document.getElementById("fc-rain")?.dataset.rainOnValue !== "false"
  }

  async toggle(event) {
    event.preventDefault()
    const on = !this.isOn()
    window.dispatchEvent(new CustomEvent("rain:set", { detail: { on } }))

    try {
      const token = document.querySelector("meta[name='csrf-token']")?.content || ""
      const res = await fetch(this.urlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": token },
        body: JSON.stringify({ on }),
        credentials: "same-origin"
      })
      if (!res.ok) throw new Error(res.status)
    } catch {
      // Didn't save: put it back so what you see matches your account.
      window.dispatchEvent(new CustomEvent("rain:set", { detail: { on: !on } }))
    }
  }

  render(on) {
    this.element.setAttribute("aria-checked", String(on))
    this.element.classList.toggle("is-on", on)
    this.labelTargets.forEach(el => { el.textContent = on ? "On" : "Off" })
  }
}
