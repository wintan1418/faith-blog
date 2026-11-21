// The inside of the GIF picker: a search box, trending GIFs while it's empty,
// a grid of previews, and loading / empty / error states. Loaded on first
// open (see lazy_libs.js). Results come from our own /gifs endpoint, which
// calls Klipy on the server so the API key never reaches the browser.
//
// Klipy's terms require "Search KLIPY" as the search placeholder.

const DEBOUNCE_MS = 350

export class GifPanel {
  constructor(root, { searchUrl, trendingUrl, onPick }) {
    this.root = root
    this.searchUrl = searchUrl
    this.trendingUrl = trendingUrl
    this.onPick = onPick
    this.query = null
    this.build()
  }

  build() {
    this.root.innerHTML = ""
    const head = el("div", "gif-head")
    this.input = el("input", "gif-search")
    Object.assign(this.input, { type: "search", placeholder: "Search KLIPY", autocomplete: "off", enterKeyHint: "search" })
    this.input.setAttribute("aria-label", "Search KLIPY for GIFs")
    // No name: it must never be sent with the message or comment.
    this.input.addEventListener("input", () => this.schedule())
    this.input.addEventListener("keydown", (event) => {
      // Enter searches; it must not send the surrounding form.
      if (event.key === "Enter") { event.preventDefault(); this.search(true) }
    })
    head.appendChild(this.input)

    this.status = el("p", "gif-state")
    this.status.setAttribute("role", "status")
    this.status.setAttribute("aria-live", "polite")
    this.grid = el("div", "gif-grid")
    this.grid.setAttribute("role", "list")

    const foot = el("p", "gif-attribution")
    foot.textContent = "Powered by KLIPY"

    this.root.append(head, this.status, this.grid, foot)
  }

  opened() {
    if (this.query === null) this.search(true)
    // On a phone, focusing pops the keyboard over the grid: let them tap the box.
    if (!window.matchMedia("(pointer: coarse)").matches) this.input.focus({ preventScroll: true })
  }

  schedule() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.search(), DEBOUNCE_MS)
  }

  async search(force = false) {
    clearTimeout(this.timer)
    const q = this.input.value.trim()
    if (!force && q === this.query) return
    this.query = q

    this.request?.abort()
    const request = this.request = new AbortController()
    this.show("Loading GIFs…")
    this.grid.setAttribute("aria-busy", "true")

    const url = new URL(q ? this.searchUrl : this.trendingUrl, window.location.origin)
    if (q) url.searchParams.set("q", q)

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" }, credentials: "same-origin", signal: request.signal
      })
      const data = await response.json().catch(() => ({}))
      if (request !== this.request) return
      if (!response.ok) throw new Error(data.error || "GIFs aren't available right now. Please try again.")
      this.render(data.results || [], q)
    } catch (error) {
      if (error.name === "AbortError") return
      this.grid.replaceChildren()
      this.show(error.message || "GIFs aren't available right now. Please try again.", "is-error")
    } finally {
      if (request === this.request) this.grid.removeAttribute("aria-busy")
    }
  }

  render(results, q) {
    this.grid.replaceChildren()
    if (!results.length) {
      this.show(q ? `No GIFs found for “${q}”. Try another word.` : "No GIFs to show right now.", "is-empty")
      return
    }
    this.show(q ? "" : "Trending", "is-label")
    for (const gif of results) {
      const button = el("button", "gif-item")
      button.type = "button"
      button.setAttribute("role", "listitem")
      button.setAttribute("aria-label", `Send GIF: ${gif.title || "GIF"}`)
      button.title = gif.title || "GIF"
      const img = el("img", "gif-item-img")
      Object.assign(img, { src: gif.preview_url, alt: gif.title || "GIF", loading: "lazy", decoding: "async" })
      button.appendChild(img)
      button.addEventListener("click", (event) => {
        event.preventDefault()
        event.stopPropagation()
        this.onPick(gif)
      })
      this.grid.appendChild(button)
    }
  }

  show(text, kind = "") {
    this.status.textContent = text
    this.status.className = `gif-state ${kind}`.trim()
    this.status.hidden = !text
  }

  destroy() {
    clearTimeout(this.timer)
    this.request?.abort()
  }
}

function el(tag, className) {
  const node = document.createElement(tag)
  if (className) node.className = className
  return node
}
