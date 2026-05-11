import { Controller } from "@hotwired/stimulus"

// Church History Arena: era tabs + figure cards + drawer for the full bio.
// Bios are AI-generated server-side on first request and cached on the row,
// so tapping a figure twice is instant after the first time.
export default class extends Controller {
  static targets = ["panel", "drawer", "drawerTitle", "drawerBody"]
  static values  = { figureUrl: String }

  connect() {
    this.boundEsc = (e) => { if (e.key === "Escape") this.closeFigure() }
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundEsc)
  }

  showEra(event) {
    const era = event.currentTarget.dataset.era
    // Tabs
    this.element.querySelectorAll(".fc-era-tab").forEach(t => {
      t.classList.toggle("is-active", t.dataset.era === era)
    })
    // Panels
    this.panelTargets.forEach(p => {
      p.classList.toggle("is-active", p.dataset.era === era)
    })
  }

  async openFigure(event) {
    const slug = event.currentTarget.dataset.slug
    if (!slug) return
    this.drawerTarget.classList.remove("hidden")
    this.drawerTarget.setAttribute("aria-hidden", "false")
    document.body.classList.add("fc-bible-open")
    document.addEventListener("keydown", this.boundEsc)

    this.drawerTitleTarget.textContent = "Loading…"
    this.drawerBodyTarget.innerHTML = `<p class="fc-bible-drawer-loading">Pulling the story…</p>`

    try {
      const url = this.figureUrlValue.replace("SLUG", encodeURIComponent(slug))
      const response = await fetch(url, { headers: { "Accept": "application/json" } })
      const payload = await response.json()
      if (!payload.ok) {
        this.drawerBodyTarget.innerHTML = `<p class="fc-bible-drawer-empty">${this.escape(payload.error || "Not found.")}</p>`
        return
      }
      this.renderBio(payload)
    } catch {
      this.drawerBodyTarget.innerHTML = `<p class="fc-bible-drawer-empty">Network error. Try again in a moment.</p>`
    }
  }

  renderBio(p) {
    this.drawerTitleTarget.textContent = p.name
    const paragraphs = (p.bio || "").split(/\n\n+/).map(s => s.trim()).filter(Boolean)
    const bioHtml = paragraphs.map(par => `<p>${this.escape(par)}</p>`).join("")
    this.drawerBodyTarget.innerHTML = `
      <p class="fc-figure-drawer-meta">
        <span class="fc-figure-drawer-era">${this.escape(p.era_label)}</span>
        ${p.years ? `<span class="fc-figure-drawer-years">${this.escape(p.years)}</span>` : ""}
      </p>
      <p class="fc-figure-drawer-claim">${this.escape(p.claim || "")}</p>
      ${p.featured_quote ? `<blockquote class="fc-figure-drawer-quote">"${this.escape(p.featured_quote)}"</blockquote>` : ""}
      <div class="fc-figure-drawer-bio">${bioHtml}</div>
    `
  }

  closeFigure() {
    if (!this.hasDrawerTarget) return
    this.drawerTarget.classList.add("hidden")
    this.drawerTarget.setAttribute("aria-hidden", "true")
    document.body.classList.remove("fc-bible-open")
    document.removeEventListener("keydown", this.boundEsc)
  }

  escape(s) {
    return String(s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"})[c])
  }
}
