import { Controller } from "@hotwired/stimulus"

// Auto-builds a Table of Contents from <h2> elements inside the post body
// and highlights the active section as the reader scrolls (IntersectionObserver).
export default class extends Controller {
  static targets = ["body", "list"]
  static classes = ["active"]

  connect() {
    if (!this.hasBodyTarget || !this.hasListTarget) return
    const headings = Array.from(this.bodyTarget.querySelectorAll("h2"))
    if (headings.length === 0) {
      this.listTarget.innerHTML = `<li class="post-toc-empty">No sections yet.</li>`
      return
    }

    this.listTarget.innerHTML = ""
    headings.forEach((h, i) => {
      if (!h.id) h.id = `section-${i}-${this.slugify(h.textContent)}`
      const li = document.createElement("li")
      const a = document.createElement("a")
      a.href = `#${h.id}`
      a.textContent = h.textContent
      a.className = "post-toc-link"
      a.dataset.tocLink = h.id
      li.appendChild(a)
      this.listTarget.appendChild(li)
    })

    this.observer = new IntersectionObserver(
      (entries) => entries.forEach(e => {
        if (!e.isIntersecting) return
        const id = e.target.id
        this.listTarget.querySelectorAll("a").forEach(a => {
          a.classList.toggle(this.activeClass || "is-active", a.dataset.tocLink === id)
        })
      }),
      { rootMargin: "-30% 0px -55% 0px", threshold: 0 }
    )
    headings.forEach(h => this.observer.observe(h))
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  slugify(text) {
    return text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 60)
  }
}
