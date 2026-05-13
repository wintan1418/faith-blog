import { Controller } from "@hotwired/stimulus"

// Controls the Repost dropdown (Quick repost vs Repost with thought)
// and the inline composer that lets the user attach a short note
// before resharing. Closes on outside click + Escape.
export default class extends Controller {
  static targets = ["trigger", "menu", "composer", "thought", "count"]
  static values  = { max: { type: Number, default: 280 } }

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
    this.composerTarget.classList.add("hidden")
    this.menuTarget.classList.remove("hidden")
    this.triggerTarget?.setAttribute("aria-expanded", "true")
    setTimeout(() => {
      document.addEventListener("mousedown", this.boundOutside, true)
      document.addEventListener("keydown", this.boundEsc)
    }, 0)
  }

  openComposer(event) {
    event?.preventDefault()
    this.menuTarget.classList.add("hidden")
    this.composerTarget.classList.remove("hidden")
    this.updateCount()
    setTimeout(() => this.thoughtTarget?.focus(), 50)
  }

  cancel(event) {
    event?.preventDefault()
    this.closeAll()
  }

  closeAll() {
    this.menuTarget.classList.add("hidden")
    this.composerTarget.classList.add("hidden")
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

  updateCount() {
    if (!this.hasCountTarget || !this.hasThoughtTarget) return
    const n = this.thoughtTarget.value.length
    this.countTarget.textContent = `${n} / ${this.maxValue}`
    this.countTarget.classList.toggle("is-near", n >= this.maxValue - 30)
  }
}
