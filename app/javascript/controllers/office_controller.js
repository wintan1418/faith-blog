import { Controller } from "@hotwired/stimulus"

// Admin → Office chat.
// - Enter sends, Shift+Enter makes a new line (on touch screens Enter is a new
//   line and the Send button sends, as phone keyboards expect).
// - The composer grows with its text.
// - The page stays pinned to the newest message as replies stream in.
// - While a reply is being written, the thread is re-fetched every few
//   seconds as a fallback in case the live connection drops.
export default class extends Controller {
  static targets = ["input", "form", "messages", "send"]
  static values = { refreshUrl: String }
  static POLL_MS = 5000

  connect() {
    this.touch = window.matchMedia("(pointer: coarse)").matches
    this.resize()
    this.scrollToBottom()
    setTimeout(() => this.scrollToBottom(), 300)

    if (this.hasMessagesTarget) {
      this.observer = new MutationObserver(() => this.scrollToBottom())
      this.observer.observe(this.messagesTarget, { childList: true, subtree: true })
    }
    this.statusObserver = new MutationObserver(() => this.syncPolling())
    this.statusObserver.observe(this.element, { childList: true, subtree: true, attributes: true, attributeFilter: ["data-thinking"] })
    this.syncPolling()
  }

  disconnect() {
    this.observer?.disconnect()
    this.statusObserver?.disconnect()
    this.stopPolling()
  }

  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing || this.touch) return
    event.preventDefault()
    if (this.inputTarget.value.trim() === "") return
    this.formTarget.requestSubmit()
  }

  resize() {
    if (!this.hasInputTarget) return
    const el = this.inputTarget
    el.style.height = "auto"
    el.style.height = `${Math.min(el.scrollHeight, 260)}px`
  }

  sending() {
    if (this.hasSendTarget) this.sendTarget.disabled = true
  }

  sent(event) {
    if (this.hasSendTarget) this.sendTarget.disabled = false
    if (event.detail.success && this.hasInputTarget) {
      this.inputTarget.value = ""
      this.resize()
    }
  }

  suggest(event) {
    this.inputTarget.value = event.currentTarget.dataset.text
    this.resize()
    this.inputTarget.focus()
  }

  copy(event) {
    const button = event.currentTarget
    navigator.clipboard?.writeText(button.dataset.text).then(() => {
      const label = button.textContent
      button.textContent = "Copied"
      setTimeout(() => { button.textContent = label }, 1500)
    })
  }

  scrollToBottom() {
    if (!this.hasRefreshUrlValue) return
    window.scrollTo({ top: document.documentElement.scrollHeight })
  }

  syncPolling() {
    const status = this.element.querySelector("#office_status")
    const thinking = status?.dataset.thinking === "true"
    if (thinking && this.hasRefreshUrlValue && this.refreshUrlValue) this.startPolling()
    else this.stopPolling()
  }

  startPolling() {
    if (this.pollTimer) return
    this.pollTimer = setInterval(() => this.refresh(), this.constructor.POLL_MS)
  }

  stopPolling() {
    clearInterval(this.pollTimer)
    this.pollTimer = null
  }

  async refresh() {
    try {
      const response = await fetch(this.refreshUrlValue, { headers: { Accept: "text/vnd.turbo-stream.html" }, credentials: "same-origin" })
      if (response.ok && window.Turbo) window.Turbo.renderStreamMessage(await response.text())
    } catch (_) {
      // Offline for a moment; the next tick tries again.
    }
  }
}
