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
  static targets = ["picker", "quick"]
  static values  = { url: String, unlikeUrl: String, token: String, mine: Boolean, quick: { type: String, default: "❤️" }, mineEmoji: String }

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
    this.hideQuick()
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

  // ── Quick-reaction pill (chat messages) ────────────────────────────────
  // One small React button; tapping it (or hovering it with a mouse) pops up
  // a floating pill of six emojis and a + for the full picker. Choosing one
  // reacts and closes it; a tap outside or Escape closes it too.
  toggleQuick(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasQuickTarget) return
    // A keyboard press (detail 0) moves focus into the pill; taps and clicks don't.
    this.quickTarget.hidden ? this.showQuick(event.currentTarget, event.detail === 0) : this.hideQuick()
  }

  hoverQuick(event) {
    if (!window.matchMedia("(hover: hover) and (pointer: fine)").matches) return
    if (this.hasQuickTarget && this.quickTarget.hidden) this.showQuick(event.currentTarget)
  }

  showQuick(button, focus = false) {
    const pill = this.quickTarget
    this.quickButton = button
    pill.hidden = false
    button.setAttribute("aria-expanded", "true")
    this.placeQuick()
    this.boundQuickOutside ||= (e) => {
      if (!this.quickTarget.contains(e.target) && e.target !== this.quickButton && !e.target.closest?.(".fc-reaction-picker")) this.hideQuick()
    }
    this.boundQuickKey ||= (e) => { if (e.key === "Escape") this.hideQuick() }
    this.boundQuickLeave ||= () => this.hideQuick()
    setTimeout(() => document.addEventListener("click", this.boundQuickOutside, true), 0)
    document.addEventListener("keydown", this.boundQuickKey)
    // Leaving the message (mouse) closes it; the menu hides with it.
    this.element.closest(".msg-item")?.addEventListener("mouseleave", this.boundQuickLeave)
    if (focus) pill.querySelector(".msg-react-quick")?.focus({ preventScroll: true })
  }

  hideQuick() {
    if (!this.hasQuickTarget || this.quickTarget.hidden) return
    this.quickTarget.hidden = true
    this.quickTarget.style.cssText = ""
    this.quickButton?.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.boundQuickOutside, true)
    document.removeEventListener("keydown", this.boundQuickKey)
    this.element.closest(".msg-item")?.removeEventListener("mouseleave", this.boundQuickLeave)
  }

  // Above the React button (below when there's no room), inside the screen.
  placeQuick() {
    const pill = this.quickTarget
    const button = this.quickButton
    if (!button) return
    const margin = 8
    Object.assign(pill.style, { position: "fixed", left: "0px", top: "0px", right: "auto", bottom: "auto" })
    // Measure without the pop-in scale, or every number comes out shrunk.
    pill.style.animation = "none"
    const origin = pill.getBoundingClientRect()
    const width = pill.offsetWidth
    const height = pill.offsetHeight
    pill.style.animation = ""
    const b = button.getBoundingClientRect()
    const head = document.querySelector(".msg-thread-head")?.getBoundingClientRect()
    const topLimit = Math.max(margin, head ? head.bottom + 4 : margin)

    let top = b.top - height - 6
    let below = false
    if (top < topLimit) { top = b.bottom + 6; below = true }
    top = Math.max(margin, Math.min(top, window.innerHeight - height - margin))
    const left = Math.max(margin, Math.min(b.left + b.width / 2 - width / 2, document.documentElement.clientWidth - width - margin))

    pill.style.left = `${Math.round(left - origin.left)}px`
    pill.style.top = `${Math.round(top - origin.top)}px`
    pill.style.transformOrigin = `${Math.round(b.left + b.width / 2 - left)}px ${below ? "top" : "bottom"}`
    pill.classList.toggle("is-below", below)
  }

  // A chat message's quick-reaction row: tap an emoji to react with it, or
  // tap the one you already chose to take it back.
  quick(event) {
    event.preventDefault()
    event.stopPropagation()
    const emoji = event.params.emoji
    if (!emoji) return
    if (emoji === this.mineEmojiValue && this.unlikeUrlValue) {
      this.hideQuick()
      return this.send(this.unlikeUrlValue, "DELETE")
    }
    return this.choose(emoji)
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
    this.hideQuick() // the full picker takes over from the quick pill
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
    this.hideQuick()
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
