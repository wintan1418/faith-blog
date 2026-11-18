import { Controller } from "@hotwired/stimulus"

// Keeps the Recent Chats list current when live updates were missed.
//
// New messages move a chat to the top over the live (Action Cable) connection.
// When the phone puts the app in the background that connection drops, so a
// message that arrives meanwhile (the one you got a push for) never reaches the
// list, and the chat was missing until a manual refresh. So: when the inbox
// comes back into view, the connection comes back, or every 30s while it's on
// screen, fetch the list again and swap in the fresh rows.
export default class extends Controller {
  static values = { every: { type: Number, default: 30000 } }

  connect() {
    this.hiddenAt = null
    this.onVisibility = () => {
      if (document.hidden) { this.hiddenAt = Date.now(); return }
      if (this.hiddenAt && Date.now() - this.hiddenAt > 2000) this.refresh()
      this.hiddenAt = null
    }
    this.onFocus = () => this.refresh()
    this.onPageShow = (event) => { if (event.persisted) this.refresh() } // back from the page cache, not first load
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("pageshow", this.onPageShow)

    // The live stream reconnecting means we may have missed broadcasts.
    const source = this.element.parentElement?.querySelector("turbo-cable-stream-source")
    if (source) {
      let wasConnected = source.hasAttribute("connected")
      let dropped = false // the first connection after page load isn't a reconnect
      this.observer = new MutationObserver(() => {
        const now = source.hasAttribute("connected")
        if (!now && wasConnected) dropped = true
        if (now && !wasConnected && dropped) this.refresh()
        wasConnected = now
      })
      this.observer.observe(source, { attributes: true, attributeFilter: [ "connected" ] })
    }

    // Live updates change the list too; a fetch started before one must not undo it.
    this.liveChangedAt = 0
    this.listObserver = new MutationObserver(() => { if (!this.swapping) this.liveChangedAt = Date.now() })
    this.listObserver.observe(this.element, { childList: true })

    this.timer = setInterval(() => { if (!document.hidden) this.refresh() }, this.everyValue)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("pageshow", this.onPageShow)
    this.observer?.disconnect()
    this.listObserver?.disconnect()
    clearInterval(this.timer)
  }

  signature(list) {
    return [ ...list.children ].map((row) => `${row.id}|${row.querySelector(".msg-row-preview, .msg-row-snippet")?.textContent?.trim() || ""}`).join("\n")
  }

  async refresh() {
    if (this.loading || Date.now() - (this.lastAt || 0) < 1000) return
    this.loading = true
    const startedAt = this.lastAt = Date.now()
    try {
      const response = await fetch(window.location.href, { headers: { Accept: "text/html" }, credentials: "same-origin" })
      if (!response.ok) return
      const doc = new DOMParser().parseFromString(await response.text(), "text/html")
      const fresh = doc.getElementById(this.element.id)
      // Swap only when the chats or their order changed, so a row isn't
      // replaced under someone's finger for nothing.
      if (this.liveChangedAt >= startedAt) return // a live update is newer than this fetch
      if (fresh && this.signature(fresh) !== this.signature(this.element)) {
        this.swapping = true
        this.element.innerHTML = fresh.innerHTML
        queueMicrotask(() => { this.swapping = false })
      }
    } catch (_) {
      // Offline or a blip: the next trigger tries again.
    } finally {
      this.loading = false
    }
  }
}
