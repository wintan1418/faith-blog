import { Controller } from "@hotwired/stimulus"

// "What's new" walk-through: slides glide across, the emoji pops in on each one,
// and finishing (or closing) remembers it so it never shows again.
export default class extends Controller {
  static targets = ["track", "slide", "dot", "next", "back"]
  static values = { seenUrl: String }

  connect() {
    this.index = 0
    this.onClose = () => this.markSeen()
    this.element.addEventListener("close", this.onClose)
    this.bindSwipe()
    // Let the page settle first, then open.
    this.openTimer = setTimeout(() => {
      if (this.element.isConnected && !this.element.open) this.element.showModal()
    }, 700)
  }

  disconnect() {
    clearTimeout(this.openTimer)
    this.element.removeEventListener("close", this.onClose)
  }

  next() {
    if (this.index >= this.slideTargets.length - 1) return this.finish()
    this.show(this.index + 1)
  }

  prev() {
    if (this.index > 0) this.show(this.index - 1)
  }

  go(event) {
    this.show(Number(event.params.index))
  }

  show(index) {
    this.index = index
    this.trackTarget.style.transform = `translateX(-${index * 100}%)`
    this.slideTargets.forEach((s, i) => {
      s.classList.toggle("is-active", i === index)
      s.setAttribute("aria-hidden", String(i !== index))
    })
    this.dotTargets.forEach((d, i) => d.classList.toggle("is-active", i === index))
    const last = index === this.slideTargets.length - 1
    this.nextTarget.textContent = last ? "Got it" : "Next"
    this.backTarget.hidden = index === 0
  }

  finish() {
    this.element.classList.add("is-leaving")
    setTimeout(() => { if (this.element.open) this.element.close() }, 220)
  }

  markSeen() {
    if (this.marked) return
    this.marked = true
    const token = document.querySelector("meta[name=csrf-token]")?.content || ""
    fetch(this.seenUrlValue, { method: "POST", credentials: "same-origin", keepalive: true, headers: { "X-CSRF-Token": token } })
  }

  bindSwipe() {
    let startX = null
    this.element.addEventListener("touchstart", (e) => { startX = e.touches[0].clientX }, { passive: true })
    this.element.addEventListener("touchend", (e) => {
      if (startX === null) return
      const dx = e.changedTouches[0].clientX - startX
      startX = null
      if (Math.abs(dx) < 45) return
      dx < 0 ? this.next() : this.prev()
    }, { passive: true })
  }
}
