import { Controller } from "@hotwired/stimulus"

// Bible drawer: browse books → chapters → verses, or run a natural-language
// search and tap a result to open the chapter. KJV via /scripture/lookup and
// /bible/search.
export default class extends Controller {
  static targets = [
    "panel", "title", "backBtn",
    "tabs", "browseTab", "searchTab",
    "browseView", "searchView", "chapterView", "readerView",
    "chapterGrid",
    "searchInput", "searchOutput",
    "output"
  ]

  connect() {
    this.boundEsc = this.onEsc.bind(this)
    this.history = []                  // ["browse"|"search"|"chapter:Book"|"reader:Ref"]
    this.currentBook = null
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
    this.showBrowse()
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

  // ── View switching ──────────────────────────────────────────────────────

  showBrowse() {
    this.swapView("browse")
    this.setTitle("Open Bible")
    this.activateTab(this.browseTabTarget)
    this.history = ["browse"]
    this.updateBackBtn()
  }

  showSearch() {
    this.swapView("search")
    this.setTitle("Search the Bible")
    this.activateTab(this.searchTabTarget)
    this.history = ["search"]
    this.updateBackBtn()
    requestAnimationFrame(() => {
      if (this.hasSearchInputTarget) this.searchInputTarget.focus()
    })
  }

  openBook(event) {
    event.preventDefault()
    const btn = event.currentTarget
    const book = btn.dataset.book
    const chapters = parseInt(btn.dataset.chapters, 10) || 1
    this.currentBook = book

    // Build the chapter grid lazily.
    const grid = this.chapterGridTarget
    grid.innerHTML = ""
    for (let i = 1; i <= chapters; i++) {
      const cell = document.createElement("button")
      cell.type = "button"
      cell.className = "fc-bible-chapter"
      cell.textContent = String(i)
      cell.dataset.action = "click->bible-drawer#openChapter"
      cell.dataset.reference = `${book} ${i}`
      grid.appendChild(cell)
    }

    this.swapView("chapter")
    this.setTitle(book)
    this.history.push(`chapter:${book}`)
    this.updateBackBtn()
  }

  openChapter(event) {
    event.preventDefault()
    const ref = event.currentTarget.dataset.reference
    if (!ref) return
    this.swapView("reader")
    this.setTitle(ref)
    this.history.push(`reader:${ref}`)
    this.updateBackBtn()
    this.lookup(ref, this.outputTarget)
  }

  // Open a chapter from a search result chip.
  openSearchHit(event) {
    event.preventDefault()
    const ref = event.currentTarget.dataset.reference
    if (!ref) return
    this.swapView("reader")
    this.setTitle(ref)
    this.history.push(`reader:${ref}`)
    this.updateBackBtn()
    this.lookup(ref, this.outputTarget)
  }

  back(event) {
    if (event) event.preventDefault()
    if (this.history.length <= 1) {
      this.showBrowse()
      return
    }
    this.history.pop()
    const top = this.history[this.history.length - 1]
    if (top === "browse") {
      this.swapView("browse")
      this.setTitle("Open Bible")
      this.activateTab(this.browseTabTarget)
    } else if (top === "search") {
      this.swapView("search")
      this.setTitle("Search the Bible")
      this.activateTab(this.searchTabTarget)
    } else if (top.startsWith("chapter:")) {
      const book = top.slice("chapter:".length)
      this.swapView("chapter")
      this.setTitle(book)
    } else if (top.startsWith("reader:")) {
      const ref = top.slice("reader:".length)
      this.swapView("reader")
      this.setTitle(ref)
    }
    this.updateBackBtn()
  }

  swapView(name) {
    const views = {
      browse:  this.browseViewTarget,
      search:  this.searchViewTarget,
      chapter: this.chapterViewTarget,
      reader:  this.readerViewTarget
    }
    Object.entries(views).forEach(([key, el]) => {
      if (!el) return
      el.classList.toggle("hidden", key !== name)
    })
    // Tabs visible only on the top-level views.
    if (this.hasTabsTarget) {
      this.tabsTarget.classList.toggle("hidden", name === "chapter" || name === "reader")
    }
  }

  setTitle(text) {
    if (this.hasTitleTarget) this.titleTarget.textContent = text
  }

  activateTab(tab) {
    if (this.hasBrowseTabTarget) this.browseTabTarget.classList.remove("is-active")
    if (this.hasSearchTabTarget) this.searchTabTarget.classList.remove("is-active")
    if (tab) tab.classList.add("is-active")
  }

  updateBackBtn() {
    if (!this.hasBackBtnTarget) return
    this.backBtnTarget.classList.toggle("hidden", this.history.length <= 1)
  }

  // ── Scripture lookup ────────────────────────────────────────────────────

  async lookup(ref, output) {
    output.innerHTML = `<p class="fc-bible-drawer-loading">Loading ${this.escape(ref)}…</p>`
    try {
      const response = await fetch(`/scripture/lookup?reference=${encodeURIComponent(ref)}`, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) {
        output.innerHTML = `<p class="fc-bible-drawer-empty">Couldn't find <strong>${this.escape(ref)}</strong>.</p>`
        return
      }
      const payload = await response.json()
      this.renderChapter(payload, output)
    } catch {
      output.innerHTML = `<p class="fc-bible-drawer-empty">Network error. Try again in a moment.</p>`
    }
  }

  renderChapter(payload, output) {
    const ref = payload.reference || ""
    const trans = payload.translation || "KJV"
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
    output.innerHTML = `
      <header class="fc-bible-read-head">
        <h2 class="fc-bible-read-ref">${this.escape(ref)}</h2>
        <span class="fc-bible-read-trans">${this.escape(trans)}</span>
      </header>
      <div class="fc-bible-read-body">${bodyHtml}</div>
    `
    output.scrollTop = 0
  }

  // ── Natural-language search ─────────────────────────────────────────────

  async runSearch(event) {
    event.preventDefault()
    const query = (this.searchInputTarget.value || "").trim()
    if (query.length < 4) return
    const out = this.searchOutputTarget
    out.innerHTML = `<p class="fc-bible-drawer-loading">Searching scripture…</p>`
    try {
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content || ""
      const response = await fetch("/bible/search", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrf
        },
        credentials: "same-origin",
        body: JSON.stringify({ query })
      })
      if (!response.ok) {
        out.innerHTML = `<p class="fc-bible-drawer-empty">Search failed. Try again in a moment.</p>`
        return
      }
      const payload = await response.json()
      this.renderSearchResults(payload, out)
    } catch {
      out.innerHTML = `<p class="fc-bible-drawer-empty">Network error. Try again in a moment.</p>`
    }
  }

  renderSearchResults(payload, out) {
    const hits = Array.isArray(payload.verses) ? payload.verses : []
    if (hits.length === 0) {
      out.innerHTML = `<p class="fc-bible-drawer-empty">No matches yet — try a different phrasing.</p>`
      return
    }
    const items = hits.map(h => `
      <li>
        <button type="button"
                class="fc-bible-hit"
                data-action="click->bible-drawer#openSearchHit"
                data-reference="${this.escape(h.reference)}">
          <span class="fc-bible-hit-ref">${this.escape(h.reference)}</span>
          ${h.reason ? `<span class="fc-bible-hit-reason">${this.escape(h.reason)}</span>` : ""}
        </button>
      </li>
    `).join("")
    out.innerHTML = `<ul class="fc-bible-hits">${items}</ul>`
  }

  // ──

  escape(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
