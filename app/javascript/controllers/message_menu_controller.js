import { Controller } from "@hotwired/stimulus"
import { copyText } from "../copy_text"

// Per-message menu: React (pops up a quick-reaction pill), Reply, Copy,
// Forward, Share, Download, Edit, Delete / Report.
//
// On desktop the .msg-actions menu shows on hover. Touch screens never hover,
// so there the menu opens from a tap on the bubble, the "⋯" button beside
// photos, files and voice notes, or a long press anywhere on the message.
//
// An open menu is pinned to the screen (position: fixed) next to its bubble
// and kept inside the screen edges. Anchored to the bubble it ran off the
// left edge beside short incoming messages, hiding the reactions (QA, Nov 2026).
const HOLD_MS = 450
const MOVE_TOLERANCE = 10
const EDGE = 8

export default class extends Controller {
  static targets = ["actions"]

  connect() {
    this.boundOutside = this.outside.bind(this)
    this.boundClose = (event) => {
      if (event?.target?.closest?.(".msg-actions, .fc-reaction-picker")) return
      this.close()
    }
    this.listening = false
  }

  disconnect() {
    this.cancelHold()
    this.stopListening()
  }

  toggle(event) {
    if (this.swallowClick(event)) return
    // Desktop keeps the hover behaviour — don't hijack real-pointer clicks.
    if (window.matchMedia("(hover: hover) and (pointer: fine)").matches) return
    if (!this.hasActionsTarget) return

    // Let interactive descendants (links, buttons, media, the menu itself)
    // behave normally instead of toggling the menu.
    if (event.target.closest("a, button, audio, input, textarea, label, img, .msg-voice-player, .msg-actions, .msg-reactions, .message-actions, .message-reactions, .fc-reaction-picker")) {
      return
    }

    this.isOpen ? this.close() : this.open()
  }

  // The "⋯" button beside photos, files and voice notes: those take taps
  // themselves, so this is how their menu opens on a phone.
  toggleFromButton(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasActionsTarget) return
    this.isOpen ? this.close() : this.open()
  }

  // Computers: the menu floats above the bubble on hover. Near the top of the
  // chat there's no room, so it opens below instead.
  hoverPlace() {
    if (!this.hasActionsTarget || this.isOpen) return
    if (!window.matchMedia("(hover: hover) and (pointer: fine)").matches) return
    const menu = this.actionsTarget
    menu.classList.remove("opens-down")
    const box = menu.getBoundingClientRect()
    if (!box.height) return
    const list = this.element.closest(".msg-messages")?.getBoundingClientRect()
    if (box.top < (list ? list.top : 0) + 4) menu.classList.add("opens-down")
  }

  // ── Long press (touch) ────────────────────────────────────────────────
  holdStart(event) {
    if (!this.hasActionsTarget || event.touches?.length !== 1) return
    if (event.target.closest(".msg-actions, .msg-reactions, .fc-reaction-picker, .msg-wave")) return
    const touch = event.touches[0]
    this.holdFrom = { x: touch.clientX, y: touch.clientY }
    this.cancelHold()
    this.holdTimer = setTimeout(() => {
      this.holdTimer = null
      this.held = true
      navigator.vibrate?.(10)
      this.open()
    }, HOLD_MS)
  }

  holdMove(event) {
    if (!this.holdTimer || !this.holdFrom) return
    const touch = event.touches[0]
    if (Math.abs(touch.clientX - this.holdFrom.x) > MOVE_TOLERANCE ||
        Math.abs(touch.clientY - this.holdFrom.y) > MOVE_TOLERANCE) this.cancelHold()
  }

  holdEnd() {
    this.cancelHold()
  }

  cancelHold() {
    clearTimeout(this.holdTimer)
    this.holdTimer = null
  }

  // Android shows its own menu (copy / save image) on a long press.
  suppressContextMenu(event) {
    if (this.held || this.holdTimer) event.preventDefault()
  }

  // The tap that ends a long press must not also open a photo or play audio.
  // Bound in the capture phase so it runs before the photo's own handler.
  swallowClick(event) {
    if (!this.held) return false
    this.held = false
    event.preventDefault()
    event.stopPropagation()
    return true
  }

  // ── Menu items ────────────────────────────────────────────────────────
  copy(event) {
    event.preventDefault()
    const button = event.currentTarget
    copyText(event.params.text).then(ok => {
      if (!ok) return
      button.classList.add("is-done")
      setTimeout(() => { button.classList.remove("is-done"); this.close() }, 700)
    })
  }

  // Several photos: open the viewer, which saves each one (its Save button).
  viewPhotos(event) {
    event.preventDefault()
    this.close()
    this.element.querySelector(".msg-image")?.click()
  }

  closeAfter() {
    // Let the link / download start first.
    setTimeout(() => this.close(), 0)
  }

  // ── Open / close ──────────────────────────────────────────────────────
  get isOpen() {
    return this.hasActionsTarget && this.actionsTarget.classList.contains("is-open")
  }

  open() {
    // Only one message menu open at a time.
    document.querySelectorAll(".msg-actions.is-open, .message-actions.is-open").forEach(el => {
      el.classList.remove("is-open")
      el.style.cssText = ""
    })
    this.actionsTarget.classList.add("is-open")
    this.element.classList.add("has-open-menu")
    this.place()
    if (!this.listening) {
      // Defer so the tap that opened us doesn't immediately close it.
      setTimeout(() => {
        document.addEventListener("click", this.boundOutside, true)
        document.addEventListener("scroll", this.boundClose, { capture: true, passive: true })
        window.addEventListener("resize", this.boundClose)
        this.listening = true
      }, 0)
    }
  }

  close() {
    if (!this.hasActionsTarget) return
    this.actionsTarget.classList.remove("is-open")
    this.actionsTarget.style.cssText = ""
    this.element.classList.remove("has-open-menu")
    // Closes the quick-reaction pill with it (emoji-reactions#hideQuick).
    this.actionsTarget.dispatchEvent(new CustomEvent("message-menu:closed"))
    this.stopListening()
  }

  stopListening() {
    if (this.listening) {
      document.removeEventListener("click", this.boundOutside, true)
      document.removeEventListener("scroll", this.boundClose, { capture: true })
      window.removeEventListener("resize", this.boundClose)
      this.listening = false
    }
  }

  outside(event) {
    if (this.element.contains(event.target)) return
    // The full emoji picker is pinned elsewhere on screen but lives inside us.
    if (event.target.closest?.("emoji-picker, .fc-reaction-picker, .msg-react-pill")) return
    this.close()
  }

  // Pin the menu above the bubble (below it when the top bar is in the way),
  // inside the screen's left and right edges.
  place() {
    const menu = this.actionsTarget
    Object.assign(menu.style, { position: "fixed", left: "0px", top: "0px", right: "auto", bottom: "auto" })
    // A transformed ancestor would offset "fixed": measure where 0,0 really lands.
    const origin = menu.getBoundingClientRect()
    const width = menu.offsetWidth
    const height = menu.offsetHeight
    const bubble = this.element.getBoundingClientRect()
    const viewW = document.documentElement.clientWidth
    const viewH = window.innerHeight

    const head = document.querySelector(".msg-thread-head")?.getBoundingClientRect()
    const topLimit = Math.max(EDGE, head ? head.bottom + 4 : EDGE)
    const composer = document.querySelector(".msg-composer")?.getBoundingClientRect()
    const bottomLimit = Math.min(viewH - EDGE, composer && composer.top > 0 ? composer.top - 4 : viewH - EDGE)

    let top = bubble.top - height - 6
    if (top < topLimit) top = bubble.bottom + 6
    if (top + height > bottomLimit) top = Math.max(topLimit, bottomLimit - height)

    const mine = this.element.closest(".msg-item")?.classList.contains("is-mine")
    let left = mine ? bubble.right - width : bubble.left
    left = Math.max(EDGE, Math.min(left, viewW - width - EDGE))

    menu.style.left = `${Math.round(left - origin.left)}px`
    menu.style.top = `${Math.round(top - origin.top)}px`
  }
}
