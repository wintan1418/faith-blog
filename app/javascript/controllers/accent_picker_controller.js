import { Controller } from "@hotwired/stimulus"

// Live-apply the chosen accent to the body CSS variables on click,
// then auto-submit the form so the choice persists. The user sees
// the change instantly — no Save button trip required.
export default class extends Controller {
  static targets = ["swatch", "form", "status"]

  pick(event) {
    const swatch = event.currentTarget
    const accent = swatch.dataset.accent
    const accent2 = swatch.dataset.accentDeep
    if (!accent || !accent2) return

    this.applyToBody(accent, accent2)
    this.markSelected(swatch)

    const radio = swatch.querySelector('input[type="radio"]')
    if (radio) {
      radio.checked = true
      radio.dispatchEvent(new Event("change", { bubbles: true }))
    }

    this.flashStatus(swatch.dataset.name)

    if (this.hasFormTarget) {
      // Slight delay so the live preview reads before the Turbo nav
      // replaces the DOM with the saved state.
      clearTimeout(this._submitTimer)
      this._submitTimer = setTimeout(() => this.formTarget.requestSubmit(), 220)
    }
  }

  applyToBody(accent, accent2) {
    const body = document.body
    const rgb = this.hexToRgb(accent).join(", ")
    body.style.setProperty("--fc-accent", accent)
    body.style.setProperty("--fc-accent-2", accent2)
    body.style.setProperty("--fc-accent-deep", accent2)
    body.style.setProperty("--fc-accent-soft", `rgba(${rgb}, 0.16)`)
    body.style.setProperty("--fc-accent-glow", `rgba(${rgb}, 0.45)`)
  }

  markSelected(swatch) {
    this.swatchTargets.forEach(s => {
      s.classList.remove("is-selected")
      const check = s.querySelector(".fc-accent-swatch-check")
      if (check) check.remove()
    })
    swatch.classList.add("is-selected")
    if (!swatch.querySelector(".fc-accent-swatch-check")) {
      const tick = document.createElement("span")
      tick.className = "fc-accent-swatch-check"
      tick.setAttribute("aria-hidden", "true")
      tick.textContent = "✓"
      swatch.appendChild(tick)
    }
  }

  flashStatus(name) {
    if (!this.hasStatusTarget || !name) return
    this.statusTarget.textContent = `${name} applied — saving…`
    this.statusTarget.classList.add("is-active")
    clearTimeout(this._statusTimer)
    this._statusTimer = setTimeout(() => {
      this.statusTarget.classList.remove("is-active")
    }, 1400)
  }

  hexToRgb(hex) {
    const h = hex.replace("#", "")
    return [h.slice(0, 2), h.slice(2, 4), h.slice(4, 6)].map(c => parseInt(c, 16))
  }
}
