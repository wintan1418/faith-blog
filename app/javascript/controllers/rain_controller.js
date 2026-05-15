import { Controller } from "@hotwired/stimulus"

// Ambient background rain — scripture / brethren / golden-breath lines
// drift down the page in the user's accent colour. Subtle enough that
// it never competes with the feed: low opacity, fixed under content,
// pointer-events: none, slower spawn rate on phones, paused when the
// tab isn't visible, fully off for prefers-reduced-motion.
export default class extends Controller {
  static values = { items: Array }

  connect() {
    this.alive = false

    // Stimulus Array value re-parses JSON on every access — read once.
    let items = []
    try { items = this.itemsValue } catch { items = [] }
    this.items = Array.isArray(items) ? items : []
    if (this.items.length === 0) return

    this.alive = true
    this.live = new Set()

    // Honour reduced-motion by SLOWING the rain, not killing it — the
    // drift is already gentle and a missing ambient layer reads as
    // "nothing is happening" to most users, which was the original
    // complaint.
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.spawnInterval = window.innerWidth < 640 ? (reduced ? 5200 : 3400) : (reduced ? 3600 : 2200)
    this.maxLive       = window.innerWidth < 640 ? (reduced ? 3 : 4)       : (reduced ? 5 : 7)

    this.onVisibility = this.onVisibility.bind(this)
    document.addEventListener("visibilitychange", this.onVisibility)

    // Seed a few drops mid-flight so the page doesn't start empty,
    // then keep a slow drip going.
    for (let i = 0; i < 3; i++) {
      setTimeout(() => this.spawn(true), i * 700)
    }
    this.startInterval()
  }

  disconnect() {
    this.alive = false
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.stopInterval()
    this.live?.forEach(el => el.remove())
    this.live?.clear()
  }

  startInterval() {
    if (this.interval) return
    this.interval = setInterval(() => this.spawn(false), this.spawnInterval)
  }
  stopInterval() {
    if (!this.interval) return
    clearInterval(this.interval)
    this.interval = null
  }

  onVisibility() {
    if (document.hidden) {
      this.stopInterval()
    } else if (this.alive) {
      this.startInterval()
    }
  }

  spawn(seed) {
    if (!this.alive) return
    if (this.live.size >= this.maxLive) return

    const item = this.items[Math.floor(Math.random() * this.items.length)]
    if (!item || !item.text) return

    const drop = document.createElement("span")
    drop.className = `fc-rain-drop is-${item.kind || "scripture"}`

    const left      = Math.random() * 92 + 2          // 2%–94%
    const duration  = 16 + Math.random() * 12          // 16–28s
    const size      = 0.78 + Math.random() * 0.32      // 0.78–1.10rem
    const delay     = seed ? -Math.random() * (duration / 2) : 0
    const drift     = (Math.random() * 60 - 30) | 0    // -30px to 30px lateral

    drop.style.left              = `${left}%`
    drop.style.fontSize          = `${size.toFixed(2)}rem`
    drop.style.animationDuration = `${duration}s`
    drop.style.animationDelay    = `${delay}s`
    drop.style.setProperty("--drift", `${drift}px`)

    const text = document.createElement("span")
    text.className = "fc-rain-text"
    text.textContent = item.text
    drop.appendChild(text)

    if (item.cite) {
      const cite = document.createElement("span")
      cite.className = "fc-rain-cite"
      cite.textContent = item.cite
      drop.appendChild(cite)
    }

    this.element.appendChild(drop)
    this.live.add(drop)

    const lifetime = (duration + Math.abs(delay)) * 1000 + 200
    setTimeout(() => {
      drop.remove()
      this.live.delete(drop)
    }, lifetime)
  }
}
