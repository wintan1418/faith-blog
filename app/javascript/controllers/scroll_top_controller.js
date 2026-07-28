import { Controller } from "@hotwired/stimulus"

// Floating "back to top" pill: appears once the user has scrolled well into
// the feed, smooth-scrolls home on tap. Respects prefers-reduced-motion.
export default class extends Controller {
  connect() {
    this.onScroll = () => {
      this.element.classList.toggle("is-visible", window.scrollY > 900)
    }
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.onScroll()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
  }

  toTop() {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    window.scrollTo({ top: 0, behavior: reduced ? "auto" : "smooth" })
  }
}
