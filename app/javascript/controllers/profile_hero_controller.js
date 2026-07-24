import { Controller } from "@hotwired/stimulus"

// Modern profile page behavior:
//   1. Count-up stats — numbers rise from 0 with an ease-out curve.
//   2. Sticky mini-bar — when the hero scrolls away, a compact bar with
//      avatar + name + follow button slides in under the topbar.
// Both respect prefers-reduced-motion.
export default class extends Controller {
  static targets = ["hero", "minibar", "count"]

  connect() {
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.countUp()
    this.watchHero()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  countUp() {
    this.countTargets.forEach(el => {
      const value = parseInt(el.dataset.count, 10)
      if (isNaN(value)) return
      if (this.reduced || value === 0) { el.textContent = this.format(value); return }

      const duration = 900
      const start = performance.now()
      const tick = now => {
        const t = Math.min((now - start) / duration, 1)
        const eased = 1 - Math.pow(1 - t, 3)
        el.textContent = this.format(Math.round(value * eased))
        if (t < 1) requestAnimationFrame(tick)
      }
      requestAnimationFrame(tick)
    })
  }

  format(n) {
    if (n >= 1_000_000) return (n / 1_000_000).toFixed(1).replace(/\.0$/, "") + "m"
    if (n >= 1_000) return (n / 1_000).toFixed(1).replace(/\.0$/, "") + "k"
    return String(n)
  }

  watchHero() {
    if (!this.hasHeroTarget || !this.hasMinibarTarget) return
    if (!("IntersectionObserver" in window)) return

    this.observer = new IntersectionObserver(entries => {
      const heroVisible = entries[0].isIntersecting
      this.minibarTarget.classList.toggle("is-visible", !heroVisible)
    }, { rootMargin: "-56px 0px 0px 0px" })

    this.observer.observe(this.heroTarget)
  }
}
