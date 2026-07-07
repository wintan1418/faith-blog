import { Controller } from "@hotwired/stimulus"

// Touch affordance for per-message actions (react / edit / delete).
//
// On desktop the .message-actions pill is revealed on hover — but touch
// devices never hover, so those actions were unreachable on a phone. Here a
// tap on the message bubble toggles an `is-open` class that reveals the pill.
// Taps that land on a link, button, media element, or the actions themselves
// are left alone so they keep their normal behaviour.
export default class extends Controller {
  static targets = ["actions"]

  connect() {
    this.boundOutside = this.outside.bind(this)
    this.listening = false
  }

  disconnect() {
    this.stopListening()
  }

  toggle(event) {
    // Desktop keeps the hover behaviour — don't hijack real-pointer clicks.
    if (window.matchMedia("(hover: hover) and (pointer: fine)").matches) return
    if (!this.hasActionsTarget) return

    // Let interactive descendants (links, buttons, media, the pill itself)
    // behave normally instead of toggling the menu.
    if (event.target.closest("a, button, audio, input, textarea, label, .message-actions, .message-reactions, .fc-reaction-picker")) {
      return
    }

    if (this.actionsTarget.classList.contains("is-open")) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    // Only one message menu open at a time.
    document.querySelectorAll(".message-actions.is-open").forEach(el => el.classList.remove("is-open"))
    this.actionsTarget.classList.add("is-open")
    if (!this.listening) {
      // Defer so the tap that opened us doesn't immediately close it.
      setTimeout(() => {
        document.addEventListener("click", this.boundOutside)
        this.listening = true
      }, 0)
    }
  }

  close() {
    this.actionsTarget.classList.remove("is-open")
    this.stopListening()
  }

  stopListening() {
    if (this.listening) {
      document.removeEventListener("click", this.boundOutside)
      this.listening = false
    }
  }

  outside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
