import { Controller } from "@hotwired/stimulus"
import { rememberDismissal } from "../remember_dismissal"

// Brethreign Celebrates: the feed banner, the strip on other pages and the
// one-time pop-up. Closing the banner/strip is remembered on the account for
// this occasion; the pop-up is remembered as soon as it opens.
let cardModule
const loadCard = () => (cardModule ||= import("../share/celebration_card").catch((error) => { cardModule = null; throw error }))

export default class extends Controller {
  static values = { key: String, popupKey: String, card: Object }

  connect() {
    if (this.popupKeyValue && this.element.tagName === "DIALOG") {
      // Let the page settle first; never on top of another open dialog.
      this.openTimer = setTimeout(() => this.openPopup(), 900)
      this.onClose = () => setTimeout(() => this.element.remove(), 300)
      this.element.addEventListener("close", this.onClose)
      this.element.addEventListener("click", (e) => { if (e.target === this.element) this.closePopup() })
    }
  }

  disconnect() {
    clearTimeout(this.openTimer)
    if (this.onClose) this.element.removeEventListener("close", this.onClose)
  }

  openPopup() {
    if (!this.element.isConnected || this.element.open) return
    if (document.querySelector("dialog[open]")) return
    rememberDismissal(this.popupKeyValue)
    if (this.element.showModal) this.element.showModal()
    else this.element.setAttribute("open", "")
  }

  closePopup() {
    if (this.element.tagName !== "DIALOG") return
    this.element.classList.add("is-leaving")
    setTimeout(() => { this.element.open ? this.element.close() : this.element.remove() }, 200)
  }

  // A button inside the pop-up was used: close it so the next thing (the
  // composer, the post) is on top.
  used() {
    if (this.element.tagName === "DIALOG" && this.element.open) this.element.close()
  }

  dismiss() {
    if (!this.keyValue) return
    rememberDismissal(this.keyValue)
    this.element.classList.add("is-leaving")
    setTimeout(() => this.element.remove(), 260)
    // The same occasion's strip/banner elsewhere on this page goes too.
    document.querySelectorAll(`[data-celebration-key-value="${this.keyValue}"]`).forEach((el) => { if (el !== this.element) el.remove() })
  }

  async sendToFriend(event) {
    event?.preventDefault()
    const data = this.cardValue
    const text = data.share_text || data.title
    const native = window.BrethreignNative
    if (native?.share) return native.share(text, data.title)
    if (navigator.share) {
      try { return await navigator.share({ title: data.title, text }) } catch (error) { if (error?.name === "AbortError") return }
    }
    try {
      await navigator.clipboard.writeText(text)
      this.toast("Greeting copied: paste it to a friend")
    } catch {
      this.toast(text)
    }
  }

  async shareCard(event) {
    event?.preventDefault()
    this.used()
    try {
      const { openCelebrationCard } = await loadCard()
      openCelebrationCard(this.cardValue)
    } catch {
      this.toast("Couldn't open the card. Check your connection.")
    }
  }

  toast(message) {
    const holder = document.getElementById("flash_messages")
    if (!holder) return
    holder.innerHTML = `<div class="fc-toast-stack" data-controller="flash">
      <div class="fc-toast is-success" role="status" data-flash-target="message">
        <span class="fc-toast-dot" aria-hidden="true"></span><span class="fc-toast-text"></span>
        <button type="button" class="fc-toast-close" data-action="click->flash#dismiss" aria-label="Dismiss">×</button>
      </div></div>`
    holder.querySelector(".fc-toast-text").textContent = message
  }
}
