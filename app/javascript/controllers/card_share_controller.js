import { Controller } from "@hotwired/stimulus"

// The business card's Share and Copy buttons: the phone's share sheet in the
// app or browser where there is one, otherwise the link is copied.
export default class extends Controller {
  static values = { url: String, title: String }

  async share(event) {
    event.preventDefault()
    const text = `${this.titleValue}\n${this.urlValue}`
    const native = window.BrethreignNative
    if (native?.share) return native.share(text, this.titleValue)
    if (navigator.share) {
      try { return await navigator.share({ title: this.titleValue, url: this.urlValue }) } catch (error) { if (error?.name === "AbortError") return }
    }
    this.copy(event)
  }

  async copy(event) {
    event?.preventDefault()
    try {
      if (window.BrethreignNative?.copy) window.BrethreignNative.copy(this.urlValue)
      else await navigator.clipboard.writeText(this.urlValue)
      this.toast("Link copied")
    } catch {
      this.toast(this.urlValue)
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
