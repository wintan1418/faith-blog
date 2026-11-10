import { Controller } from "@hotwired/stimulus"

// Hover/tap tooltip for the admin dashboard bar charts: reads data-tip from the bar under the pointer.
export default class extends Controller {
  static targets = ["tip"]

  connect() {
    this.move = this.move.bind(this)
    this.hide = this.hide.bind(this)
    this.element.addEventListener("pointermove", this.move)
    this.element.addEventListener("pointerdown", this.move)
    this.element.addEventListener("pointerleave", this.hide)
  }

  disconnect() {
    this.element.removeEventListener("pointermove", this.move)
    this.element.removeEventListener("pointerdown", this.move)
    this.element.removeEventListener("pointerleave", this.hide)
  }

  move(event) {
    const bar = event.target.closest("[data-tip]")
    if (!bar) return this.hide()

    this.element.querySelectorAll(".is-hover").forEach((el) => el.classList.remove("is-hover"))
    bar.classList.add("is-hover")
    const box = this.element.getBoundingClientRect()
    const tip = this.tipTarget
    tip.textContent = bar.dataset.tip
    tip.hidden = false
    const x = Math.min(Math.max(event.clientX - box.left, tip.offsetWidth / 2), box.width - tip.offsetWidth / 2)
    tip.style.left = `${x}px`
  }

  hide() {
    this.tipTarget.hidden = true
    this.element.querySelectorAll(".is-hover").forEach((el) => el.classList.remove("is-hover"))
  }
}
