import { Controller } from "@hotwired/stimulus"

// Keeps a conversation thread anchored to the newest message.
//
// On open: jump straight to the bottom (no animation — the user shouldn't
// watch the whole history fly past). While open: new messages appended by
// Turbo Streams re-pin the scroller, but only if the reader was already
// near the bottom OR the message is their own — someone scrolled up
// reading history must never be yanked down by an incoming message.
export default class extends Controller {
  static NEAR_BOTTOM_PX = 120

  connect() {
    this.jumpToBottom()
    // Fonts and images settle after first paint and grow the scroll height;
    // re-pin once they've had a beat.
    requestAnimationFrame(() => this.jumpToBottom())
    this.settleTimer = setTimeout(() => this.jumpToBottom(), 250)

    // Images that finish loading later grow the thread; stay pinned if the
    // reader is at the bottom. `load` doesn't bubble — capture it.
    this.onLoad = () => { if (this.nearBottom()) this.jumpToBottom() }
    this.element.addEventListener("load", this.onLoad, true)

    this.observer = new MutationObserver((mutations) => this.onAppend(mutations))
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
    clearTimeout(this.settleTimer)
    this.element.removeEventListener("load", this.onLoad, true)
  }

  onAppend(mutations) {
    const added = mutations.flatMap((m) => Array.from(m.addedNodes))
      .filter((n) => n.nodeType === Node.ELEMENT_NODE)
    if (added.length === 0) return

    const mine = added.some((n) => n.classList?.contains("is-mine"))
    if (mine || this.nearBottom()) {
      requestAnimationFrame(() => this.element.scrollTo({ top: this.element.scrollHeight, behavior: "smooth" }))
    }
  }

  nearBottom() {
    const el = this.element
    return el.scrollHeight - el.scrollTop - el.clientHeight < this.constructor.NEAR_BOTTOM_PX
  }

  jumpToBottom() {
    // The container has `scroll-behavior: smooth` in CSS; "instant"
    // overrides it so opening a long thread doesn't animate.
    this.element.scrollTo({ top: this.element.scrollHeight, behavior: "instant" })
  }
}
