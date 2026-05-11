import { Controller } from "@hotwired/stimulus"

// Full-screen image lightbox. Mounted on any element that wraps a set of
// <img> children (e.g. .fc-breath-media-grid). Clicking an image opens the
// full-screen viewer with arrow/swipe navigation between siblings.
export default class extends Controller {
  connect() {
    this.imgs = Array.from(this.element.querySelectorAll("img"))
    if (this.imgs.length === 0) return
    this.boundOpen = this.open.bind(this)
    this.imgs.forEach((img, i) => {
      img.style.cursor = "zoom-in"
      img.addEventListener("click", (e) => {
        e.preventDefault()
        e.stopPropagation()
        this.boundOpen(i)
      })
    })
  }

  open(startIndex = 0) {
    this.index = startIndex
    this.overlay = this.buildOverlay()
    document.body.appendChild(this.overlay)
    document.body.classList.add("fc-lightbox-open")
    this.render()
    this.boundKey = (e) => this.onKey(e)
    document.addEventListener("keydown", this.boundKey)
  }

  close() {
    if (this.overlay) {
      this.overlay.remove()
      this.overlay = null
    }
    document.body.classList.remove("fc-lightbox-open")
    if (this.boundKey) document.removeEventListener("keydown", this.boundKey)
  }

  next() {
    if (this.imgs.length <= 1) return
    this.index = (this.index + 1) % this.imgs.length
    this.render()
  }

  prev() {
    if (this.imgs.length <= 1) return
    this.index = (this.index - 1 + this.imgs.length) % this.imgs.length
    this.render()
  }

  onKey(event) {
    if (event.key === "Escape") this.close()
    else if (event.key === "ArrowRight") this.next()
    else if (event.key === "ArrowLeft") this.prev()
  }

  render() {
    const src = this.imgs[this.index].src
    const img = this.overlay.querySelector(".fc-lightbox-img")
    img.src = src
    const counter = this.overlay.querySelector(".fc-lightbox-counter")
    if (counter) {
      counter.textContent = this.imgs.length > 1 ? `${this.index + 1} / ${this.imgs.length}` : ""
    }
    const prev = this.overlay.querySelector(".fc-lightbox-prev")
    const next = this.overlay.querySelector(".fc-lightbox-next")
    if (prev) prev.style.display = this.imgs.length > 1 ? "" : "none"
    if (next) next.style.display = this.imgs.length > 1 ? "" : "none"
  }

  buildOverlay() {
    const overlay = document.createElement("div")
    overlay.className = "fc-lightbox"
    overlay.innerHTML = `
      <button class="fc-lightbox-close" aria-label="Close">×</button>
      <button class="fc-lightbox-prev" aria-label="Previous">‹</button>
      <button class="fc-lightbox-next" aria-label="Next">›</button>
      <span class="fc-lightbox-counter"></span>
      <img class="fc-lightbox-img" alt="">
    `
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) this.close()
    })
    overlay.querySelector(".fc-lightbox-close").addEventListener("click", () => this.close())
    overlay.querySelector(".fc-lightbox-prev").addEventListener("click", () => this.prev())
    overlay.querySelector(".fc-lightbox-next").addEventListener("click", () => this.next())

    // Swipe for touch.
    let startX = 0
    overlay.addEventListener("touchstart", (e) => { startX = e.touches[0].clientX }, { passive: true })
    overlay.addEventListener("touchend", (e) => {
      const dx = e.changedTouches[0].clientX - startX
      if (Math.abs(dx) < 40) return
      if (dx < 0) this.next()
      else this.prev()
    }, { passive: true })

    return overlay
  }
}
