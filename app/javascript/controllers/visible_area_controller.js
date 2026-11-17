import { Controller } from "@hotwired/stimulus"

// Keeps a full-screen sheet (the phone composer) inside the part of the screen
// you can actually see.
//
// In the iPhone/Android apps the page's layout area also counts the space under
// the app's own top bar, so a `height: 100%` sheet ran past the bottom and its
// Breathe row sat out of reach. The visual viewport is the visible area (and it
// shrinks when the keyboard opens), so size the sheet to it.
export default class extends Controller {
  static values = { maxWidth: { type: Number, default: 520 } }

  connect() {
    this.fit = () => {
      cancelAnimationFrame(this.frame)
      this.frame = requestAnimationFrame(() => this.apply())
    }
    window.visualViewport?.addEventListener("resize", this.fit)
    window.visualViewport?.addEventListener("scroll", this.fit)
    window.addEventListener("resize", this.fit)
    this.observer = new MutationObserver(this.fit)
    this.observer.observe(this.element, { attributes: true, attributeFilter: [ "open" ] })
    this.fit()
  }

  disconnect() {
    window.visualViewport?.removeEventListener("resize", this.fit)
    window.visualViewport?.removeEventListener("scroll", this.fit)
    window.removeEventListener("resize", this.fit)
    this.observer?.disconnect()
    cancelAnimationFrame(this.frame)
  }

  apply() {
    const vv = window.visualViewport
    const phone = window.matchMedia(`(max-width: ${this.maxWidthValue}px)`).matches
    if (!vv || !phone || !this.element.open) {
      this.element.style.removeProperty("--visible-h")
      this.element.style.removeProperty("--visible-top")
      return
    }
    this.element.style.setProperty("--visible-h", `${Math.round(vv.height)}px`)
    this.element.style.setProperty("--visible-top", `${Math.round(vv.offsetTop)}px`)
  }
}
