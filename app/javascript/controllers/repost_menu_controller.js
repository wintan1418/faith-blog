import { Controller } from "@hotwired/stimulus"

// Controls the Repost dropdown (Quick repost vs Quote). The Quote option
// is a regular link — it navigates to /posts/new?quote=ID where the full
// composer opens with the original post embedded as a preview.
// Closes on outside click + Escape.
export default class extends Controller {
  static targets = ["trigger", "menu"]

  connect() {
    this.boundOutside = this.outsideClick.bind(this)
    this.boundEsc = this.onEsc.bind(this)
  }

  disconnect() {
    document.removeEventListener("mousedown", this.boundOutside, true)
    document.removeEventListener("keydown", this.boundEsc)
  }

  toggleMenu(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this.menuTarget.classList.contains("hidden")) {
      this.openMenu()
    } else {
      this.closeAll()
    }
  }

  openMenu() {
    this.menuTarget.classList.remove("hidden")
    this.triggerTarget?.setAttribute("aria-expanded", "true")
    setTimeout(() => {
      document.addEventListener("mousedown", this.boundOutside, true)
      document.addEventListener("keydown", this.boundEsc)
    }, 0)
  }

  closeAll() {
    this.menuTarget.classList.add("hidden")
    this.triggerTarget?.setAttribute("aria-expanded", "false")
    document.removeEventListener("mousedown", this.boundOutside, true)
    document.removeEventListener("keydown", this.boundEsc)
  }

  outsideClick(event) {
    if (!this.element.contains(event.target)) this.closeAll()
  }

  onEsc(event) {
    if (event.key === "Escape") this.closeAll()
  }
}
