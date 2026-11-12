import { Controller } from "@hotwired/stimulus"
import { copyText } from "../copy_text"

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

    // Only follow new messages while the reader is at the bottom; changes to
    // a card further up (an image added, a picker loading) don't jump the page.
    this.pinned = true
    this.onScroll = () => { this.pinned = this.nearBottom() }
    window.addEventListener("scroll", this.onScroll, { passive: true })

    if (this.hasMessagesTarget) {
      this.observer = new MutationObserver(() => { if (this.pinned) this.scrollToBottom() })
      this.observer.observe(this.messagesTarget, { childList: true, subtree: true })
    }
    this.statusObserver = new MutationObserver(() => this.syncPolling())
    this.statusObserver.observe(this.element, { childList: true, subtree: true, attributes: true, attributeFilter: ["data-thinking"] })
    this.syncPolling()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
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
    this.pinned = true
    this.scrollToBottom()
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

  // Copies the complete text from the <template> beside the button (never
  // the rendered page). copyText uses the Android app's bridge, then the
  // Clipboard API, then a hidden textarea for older WebViews.
  async copy(event) {
    const button = event.currentTarget
    const source = button.parentElement?.querySelector("template[data-office-copy-source]")
    const text = source ? source.content.textContent : (button.dataset.text || "")
    const ok = await copyText(text)
    const label = button.dataset.label || button.textContent
    button.textContent = ok ? "Copied" : "Couldn't copy"
    clearTimeout(button._copyTimer)
    button._copyTimer = setTimeout(() => { button.textContent = label }, 1600)
  }

  // Pickers on cards load into a lazy turbo frame; reopening one reloads it
  // so flyers and breaths made since then appear.
  loadPicker(event) {
    const details = event.currentTarget
    if (!details.open) return
    const frame = details.querySelector("turbo-frame[src]")
    if (frame && frame.complete) frame.reload()
  }

  // Upload as soon as a file is chosen (after checking its size here too).
  upload(event) {
    const input = event.currentTarget
    const file = input.files?.[0]
    if (!file) return
    const max = Number(input.dataset.maxBytes || 0)
    if (max && file.size > max) {
      alert(`That image is too large (max ${Math.round(max / 1048576)}MB).`)
      input.value = ""
      return
    }
    input.form.requestSubmit()
  }

  nearBottom() {
    const doc = document.documentElement
    return doc.scrollHeight - (window.scrollY + window.innerHeight) < 160
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
