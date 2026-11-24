import { Controller } from "@hotwired/stimulus"

// Instant search for a search box (the header's and the search page's).
//
// Typing waits ~200ms, then asks /search/suggest for a few people, rooms and
// breaths; a newer keystroke aborts the request in flight, and an answer for
// text that's no longer in the box is dropped. An empty box shows the
// member's recent searches (clearable). ARIA combobox: arrow keys move
// through the options, Enter opens one (Turbo, so the iOS/Android apps stay
// in place), Escape closes.
//
// In the top bar on narrower screens the box is hidden behind a round button;
// `open` shows it as an overlay.
const DEBOUNCE_MS = 200

export default class extends Controller {
  static targets = ["input", "panel"]
  static values = { url: String, clearUrl: String }

  connect() {
    this.timer = null
    this.request = null
    this.activeIndex = -1
    this.lastQuery = null
    this.boundDocumentClick = (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    document.addEventListener("click", this.boundDocumentClick)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.request?.abort()
    document.removeEventListener("click", this.boundDocumentClick)
  }

  // Header round button on narrow screens: reveal the box instead of leaving the page.
  open(event) {
    if (!this.hasInputTarget) return
    event?.preventDefault()
    this.element.classList.add("is-open")
    this.inputTarget.focus()
  }

  dismiss() {
    this.close()
    this.element.classList.remove("is-open")
  }

  focus() {
    this.load()
  }

  input() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), DEBOUNCE_MS)
  }

  keydown(event) {
    const options = this.options
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        if (this.panelTarget.hidden) { this.load(); return }
        this.highlight(options.length ? (this.activeIndex + 1) % options.length : -1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.highlight(options.length ? (this.activeIndex <= 0 ? options.length - 1 : this.activeIndex - 1) : -1)
        break
      case "Enter": {
        const option = options[this.activeIndex]
        if (option && !this.panelTarget.hidden) {
          event.preventDefault()
          this.choose(option)
        }
        break
      }
      case "Escape":
        if (!this.panelTarget.hidden) {
          event.preventDefault()
          this.close()
        } else if (this.element.classList.contains("is-open")) {
          this.dismiss()
          this.inputTarget.blur()
        }
        break
      case "Tab":
        this.close()
        break
    }
  }

  // Focus left the whole widget (Tab, tapping elsewhere): close it.
  focusout(event) {
    if (event.relatedTarget && this.element.contains(event.relatedTarget)) return
    setTimeout(() => {
      if (!this.element.contains(document.activeElement)) this.dismiss()
    }, 120)
  }

  pick(event) {
    const option = event.target.closest('[role="option"]')
    if (!option) return
    event.preventDefault()
    this.choose(option)
  }

  async clearRecent(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.clearUrlValue) return
    const token = document.querySelector('meta[name="csrf-token"]')?.content || ""
    try {
      await fetch(this.clearUrlValue, {
        method: "DELETE",
        headers: { "X-CSRF-Token": token, Accept: "text/html" },
        credentials: "same-origin"
      })
    } catch (_) { /* offline: leave the list as it is */ }
    this.lastQuery = null
    this.load()
    this.inputTarget.focus()
  }

  async load() {
    if (!this.hasPanelTarget || !this.urlValue) return
    const query = this.inputTarget.value.trim()
    if (query === this.lastQuery && !this.panelTarget.hidden) return

    this.request?.abort()
    const request = new AbortController()
    this.request = request
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", query)
    this.element.setAttribute("aria-busy", "true")
    try {
      const response = await fetch(url, {
        headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin",
        signal: request.signal
      })
      if (!response.ok) return // rate limited or offline: the form still works
      const html = await response.text()
      if (this.request !== request || this.inputTarget.value.trim() !== query) return // stale
      this.lastQuery = query
      this.panelTarget.innerHTML = html
      this.activeIndex = -1
      this.inputTarget.removeAttribute("aria-activedescendant")
      if (this.panelTarget.querySelector("[data-search-suggest-empty]") && !query) {
        this.close()
      } else {
        this.show()
      }
    } catch (error) {
      if (error.name !== "AbortError") this.close()
    } finally {
      if (this.request === request) this.element.removeAttribute("aria-busy")
    }
  }

  get options() {
    return this.hasPanelTarget ? Array.from(this.panelTarget.querySelectorAll('[role="option"]')) : []
  }

  highlight(index) {
    const options = this.options
    options.forEach((option, i) => option.setAttribute("aria-selected", i === index ? "true" : "false"))
    this.activeIndex = index
    const active = options[index]
    if (active) {
      this.inputTarget.setAttribute("aria-activedescendant", active.id)
      active.scrollIntoView({ block: "nearest" })
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
  }

  choose(option) {
    const href = option.getAttribute("href") || option.dataset.href
    if (option.dataset.query !== undefined) this.inputTarget.value = option.dataset.query
    this.dismiss()
    if (!href) return
    if (window.Turbo) window.Turbo.visit(href)
    else window.location.href = href
  }

  show() {
    this.panelTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    if (!this.hasPanelTarget) return
    this.panelTarget.hidden = true
    this.activeIndex = -1
    this.inputTarget?.setAttribute("aria-expanded", "false")
    this.inputTarget?.removeAttribute("aria-activedescendant")
  }
}
