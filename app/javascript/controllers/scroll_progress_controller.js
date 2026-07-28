import { Controller } from "@hotwired/stimulus"

// Hairline reading-progress bar: scales with how far down the page you are.
// Uses transform: scaleX (GPU-composited) and an rAF gate so the scroll
// handler stays cheap even on modest phones.
export default class extends Controller {
  static targets = ["bar"]

  connect() {
    this.ticking = false
    this.onScroll = () => {
      if (this.ticking) return
      this.ticking = true
      requestAnimationFrame(() => {
        this.ticking = false
        const max = document.documentElement.scrollHeight - window.innerHeight
        const ratio = max > 0 ? Math.min(window.scrollY / max, 1) : 0
        this.barTarget.style.transform = `scaleX(${ratio})`
      })
    }
    window.addEventListener("scroll", this.onScroll, { passive: true })
    window.addEventListener("resize", this.onScroll, { passive: true })
    this.onScroll()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    window.removeEventListener("resize", this.onScroll)
  }
}
