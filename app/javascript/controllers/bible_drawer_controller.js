import { Controller } from "@hotwired/stimulus"

// Right-side slide-in drawer for reading scripture. Calls /scripture/lookup
// (KJV via bible-api.com) and renders verses cleanly without leaving the page.
export default class extends Controller {
  static targets = ["panel", "input", "output"]

  connect() {
    this.boundEsc = this.onEsc.bind(this)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundEsc)
  }

  open(event) {
    if (event) event.preventDefault()
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.remove("hidden")
    this.panelTarget.setAttribute("aria-hidden", "false")
    document.body.classList.add("fc-bible-open")
    document.addEventListener("keydown", this.boundEsc)
    requestAnimationFrame(() => {
      if (this.hasInputTarget) this.inputTarget.focus()
    })
  }

  close(event) {
    if (event) event.preventDefault()
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.add("hidden")
    this.panelTarget.setAttribute("aria-hidden", "true")
    document.body.classList.remove("fc-bible-open")
    document.removeEventListener("keydown", this.boundEsc)
  }

  onEsc(event) {
    if (event.key === "Escape") this.close()
  }

  search(event) {
    event.preventDefault()
    const ref = (this.inputTarget.value || "").trim()
    if (ref) this.lookup(ref)
  }

  quicklink(event) {
    event.preventDefault()
    const ref = event.currentTarget.dataset.reference
    if (!ref) return
    if (this.hasInputTarget) this.inputTarget.value = ref
    this.lookup(ref)
  }

  async lookup(ref) {
    if (!this.hasOutputTarget) return
    this.outputTarget.innerHTML = `<p class="fc-bible-drawer-loading">Loading ${this.escape(ref)}…</p>`
    try {
      const response = await fetch(`/scripture/lookup?reference=${encodeURIComponent(ref)}`, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) {
        this.outputTarget.innerHTML = `<p class="fc-bible-drawer-empty">Couldn't find <strong>${this.escape(ref)}</strong>. Try a reference like "John 3" or "Psalm 23:1-6".</p>`
        return
      }
      const payload = await response.json()
      this.render(payload)
    } catch {
      this.outputTarget.innerHTML = `<p class="fc-bible-drawer-empty">Network error. Try again in a moment.</p>`
    }
  }

  render(payload) {
    const ref = payload.reference || ""
    const trans = payload.translation || "KJV"

    // Prefer per-verse rendering when the API returned a verses array.
    // Fall back to splitting the raw `text` on newlines for older cache hits.
    let bodyHtml = ""
    if (Array.isArray(payload.verses) && payload.verses.length > 0) {
      bodyHtml = payload.verses.map(v => `
        <p class="fc-bible-verse">
          <span class="fc-bible-verse-num">${this.escape(String(v.verse))}</span>
          <span class="fc-bible-verse-text">${this.escape(v.text)}</span>
        </p>
      `).join("")
    } else {
      const lines = String(payload.text || "").split(/\n+/).map(s => s.trim()).filter(Boolean)
      bodyHtml = lines.map(l => `<p class="fc-bible-verse"><span class="fc-bible-verse-text">${this.escape(l)}</span></p>`).join("")
    }

    this.outputTarget.innerHTML = `
      <header class="fc-bible-read-head">
        <h2 class="fc-bible-read-ref">${this.escape(ref)}</h2>
        <span class="fc-bible-read-trans">${this.escape(trans)}</span>
      </header>
      <div class="fc-bible-read-body">${bodyHtml}</div>
    `
    this.outputTarget.scrollTop = 0
  }

  escape(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
