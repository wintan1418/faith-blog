import { Controller } from "@hotwired/stimulus"

// Auto-cycling carousel for the Golden Breaths sidebar card.
// Pauses on hover. Click dots / arrows to jump.
export default class extends Controller {
  static targets = ["slide", "dot", "track"]
  static values  = { interval: { type: Number, default: 7000 } }

  connect() {
    this.index = 0
    this.start()
    this.element.addEventListener("mouseenter", () => this.stop())
    this.element.addEventListener("mouseleave", () => this.start())
  }

  disconnect() {
    this.stop()
  }

  start() {
    if (this.slideTargets.length < 2) return
    this.stop()
    this.timer = setInterval(() => this.next(), this.intervalValue)
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  next(event) {
    if (event) event.preventDefault()
    this.show((this.index + 1) % this.slideTargets.length)
  }

  prev(event) {
    if (event) event.preventDefault()
    const total = this.slideTargets.length
    this.show((this.index - 1 + total) % total)
  }

  goto(event) {
    event.preventDefault()
    const i = parseInt(event.currentTarget.dataset.index, 10)
    if (Number.isNaN(i)) return
    this.show(i)
    this.start() // restart timer after manual nav
  }

  show(i) {
    this.slideTargets.forEach((s, n) => s.classList.toggle("is-active", n === i))
    this.dotTargets.forEach((d, n) => d.classList.toggle("is-active", n === i))
    this.index = i
  }
}
