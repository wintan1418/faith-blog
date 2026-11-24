import { Controller } from "@hotwired/stimulus"
import { iconLabel } from "../helpers/ui_icons"

// "Invite friends": copy the personal invite link or the ready-to-send
// message, and open the phone's share sheet where there is one.
export default class extends Controller {
  static targets = ["input", "copyBtn", "message", "messageBtn", "nativeBtn"]
  static values = { message: String, title: String, url: String }

  connect() {
    if (this.hasNativeBtnTarget && typeof navigator.share === "function") this.nativeBtnTarget.hidden = false
  }

  select(event) {
    event.target.select()
  }

  copy(event) {
    event.preventDefault()
    if (this.hasInputTarget) this.copyText(this.inputTarget, this.hasCopyBtnTarget ? this.copyBtnTarget : null)
  }

  copyMessage(event) {
    event.preventDefault()
    if (this.hasMessageTarget) this.copyText(this.messageTarget, this.hasMessageBtnTarget ? this.messageBtnTarget : null)
  }

  async share(event) {
    event.preventDefault()
    try {
      await navigator.share({ title: this.titleValue, text: this.messageValue, url: this.urlValue })
    } catch (error) {
      // Closing the share sheet is not an error worth showing.
      if (error && error.name !== "AbortError" && this.hasInputTarget) this.copyText(this.inputTarget, this.copyBtnTarget)
    }
  }

  async copyText(field, button) {
    const text = field.value
    try {
      await navigator.clipboard.writeText(text)
      this.flash(button, iconLabel("check", "Copied"))
    } catch {
      // Older browsers: select + execCommand
      field.focus()
      field.select()
      try { document.execCommand("copy"); this.flash(button, iconLabel("check", "Copied")) }
      catch { this.flash(button, "Couldn't copy") }
    }
  }

  flash(button, html) {
    if (!button) return
    if (!button.dataset.original) button.dataset.original = button.innerHTML
    button.innerHTML = html
    button.disabled = true
    clearTimeout(button._inviteTimer)
    button._inviteTimer = setTimeout(() => {
      button.innerHTML = button.dataset.original
      button.disabled = false
    }, 1400)
  }
}
