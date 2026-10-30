import { Controller } from "@hotwired/stimulus"
import { loadEmojiPicker } from "../lazy_libs"

// Pop emoji picker, send the chosen emoji to /likes via fetch.
// On success, reload the page (or replace the reactions partial) so
// counts and "is-mine" state refresh.
export default class extends Controller {
  static targets = ["picker"]
  static values  = { url: String, token: String }

  connect() {
    this.boundOutsideClick = this.outsideClick.bind(this)
    if (this.hasPickerTarget) {
      const inner = this.pickerTarget.querySelector("emoji-picker")
      if (inner && !inner._wired) {
        inner.addEventListener("emoji-click", e => this.choose(e.detail.unicode))
        inner._wired = true
      }
    }
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutsideClick)
    this.stopFollowingScroll()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasPickerTarget) return
    loadEmojiPicker()

    const visible = !this.pickerTarget.classList.contains("hidden")
    if (visible) {
      this.hide()
    } else {
      this.trigger = event.currentTarget
      this.show()
    }
  }

  show() {
    this.pickerTarget.classList.remove("hidden")
    this.place()
    setTimeout(() => document.addEventListener("click", this.boundOutsideClick), 50)
    this.boundHideOnScroll ||= () => this.hide()
    // Page scrolls only (not the picker's own list): it's pinned to the screen.
    window.addEventListener("scroll", this.boundHideOnScroll, { passive: true })
  }

  hide() {
    this.pickerTarget.classList.add("hidden")
    document.removeEventListener("click", this.boundOutsideClick)
    this.stopFollowingScroll()
  }

  stopFollowingScroll() {
    if (this.boundHideOnScroll) window.removeEventListener("scroll", this.boundHideOnScroll)
  }

  // Pin the picker on screen next to the button that opened it: above when
  // there's room, otherwise below, never past the screen edges. CSS alone
  // placed it relative to whichever ancestor happened to be positioned, so on
  // a breath's own page it opened far off screen and reacting did nothing.
  place() {
    const picker = this.pickerTarget
    const button = this.trigger
    if (!button) return
    const margin = 8
    const header = 64 // the sticky top bar covers the top of the screen
    Object.assign(picker.style, { position: "fixed", left: "0px", top: "0px", right: "auto", bottom: "auto", marginTop: "0" })
    picker.style.animation = "none"
    // A transformed ancestor would offset "fixed": measure where 0,0 really lands.
    const origin = picker.getBoundingClientRect()
    picker.style.animation = ""
    const width = picker.offsetWidth
    const height = picker.offsetHeight
    const b = button.getBoundingClientRect()

    let top = b.top - height - margin
    if (top < header) top = b.bottom + margin
    top = Math.max(margin, Math.min(top, window.innerHeight - height - margin))
    const left = Math.max(margin, Math.min(b.left, window.innerWidth - width - margin))

    picker.style.left = `${left - origin.left}px`
    picker.style.top = `${top - origin.top}px`
    picker.style.transformOrigin = top < b.top ? "bottom left" : "top left"
  }

  outsideClick(event) {
    if (!this.element.contains(event.target)) this.hide()
  }

  async choose(emoji) {
    this.hide()

    const form = new FormData()
    form.set("authenticity_token", this.tokenValue)
    form.set("reaction_emoji", emoji)

    try {
      // urlValue already carries likeable_type/id as query params; preserve them.
      const response = await fetch(this.urlValue, {
        method: "POST",
        body: form,
        headers: { "Accept": "text/vnd.turbo-stream.html, text/html" },
        credentials: "same-origin"
      })

      if (!response.ok && !response.redirected) {
        console.error("Reaction failed:", response.status, await response.text())
        return
      }

      const text = await response.text()
      const ct = response.headers.get("content-type") || ""
      if (ct.includes("turbo-stream") && window.Turbo) {
        window.Turbo.renderStreamMessage(text)
      } else {
        // Fallback: full reload if the server didn't return a stream.
        window.location.reload()
      }
    } catch (err) {
      console.error(err)
    }
  }
}
