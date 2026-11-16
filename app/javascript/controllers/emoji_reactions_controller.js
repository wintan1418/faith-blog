import { Controller } from "@hotwired/stimulus"
import { loadEmojiPicker } from "../lazy_libs"

// Pop emoji picker, send the chosen emoji to /likes via fetch.
// On success, reload the page (or replace the reactions partial) so
// counts and "is-mine" state refresh.
//
// The feed's Like button (action "press"): a tap Loves the breath at once and
// a second tap takes it back; holding it (or right-clicking) opens the picker
// for the other reactions. Testers found a picker on every tap too much for
// a simple like.
const HOLD_MS = 450

export default class extends Controller {
  static targets = ["picker"]
  static values  = { url: String, unlikeUrl: String, token: String, mine: Boolean, quick: { type: String, default: "❤️" } }

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
    this.cancelHold()
  }

  // pointerdown: start the hold timer; holding opens the picker.
  holdStart(event) {
    if (event.button > 0) return
    this.held = false
    this.cancelHold()
    const button = event.currentTarget
    this.holdTimer = setTimeout(() => {
      this.held = true
      this.openPicker(button)
      navigator.vibrate?.(10)
    }, HOLD_MS)
  }

  cancelHold() {
    clearTimeout(this.holdTimer)
    this.holdTimer = null
  }

  // click: a quick tap reacts (or takes the reaction back); the click that
  // ends a hold does nothing, the picker is already open.
  press(event) {
    event.preventDefault()
    event.stopPropagation()
    this.cancelHold()
    if (this.held) { this.held = false; return }
    if (this.hasPickerTarget && !this.pickerTarget.classList.contains("hidden")) return this.hide()
    if (this.mineValue && this.unlikeUrlValue) this.send(this.unlikeUrlValue, "DELETE")
    else this.choose(this.quickValue)
  }

  // Right-click (and a long press on some phones) opens the picker too.
  more(event) {
    event.preventDefault()
    this.cancelHold()
    this.held = true
    this.openPicker(event.currentTarget)
  }

  openPicker(button) {
    if (!this.hasPickerTarget) return
    loadEmojiPicker()
    this.trigger = button
    this.show()
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

  choose(emoji) {
    this.hide()
    const form = new FormData()
    form.set("reaction_emoji", emoji)
    // urlValue already carries likeable_type/id as query params; preserve them.
    return this.send(this.urlValue, "POST", form)
  }

  async send(url, method, form = new FormData()) {
    if (this.sending) return
    this.sending = true
    form.set("authenticity_token", this.tokenValue)
    if (method !== "POST") form.set("_method", method.toLowerCase())

    try {
      const response = await fetch(url, {
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
    } finally {
      this.sending = false
    }
  }
}
