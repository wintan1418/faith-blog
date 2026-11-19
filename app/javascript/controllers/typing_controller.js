import { Controller } from "@hotwired/stimulus"
import { subscribeTyping } from "../channels/typing_hub"

const TYPING_THROTTLE_MS = 3000

// "Name is typing…" in an open chat: animated dots in the thread and a green
// "typing…" under the name in the header (the element gets .is-typing).
export default class extends Controller {
  static values = {
    conversationId: Number,
    userId: Number,
    username: String
  }

  static targets = ["indicator", "input"]

  connect() {
    this.hideTimer = null
    this.stopTimer = null
    this.lastSentAt = 0      // when we last told the others "typing"
    this.announced = false   // whether they currently think we're typing
    this.subscription = subscribeTyping(this.conversationIdValue, (data) => this.received(data))
  }

  disconnect() {
    this.stopTyping()
    if (this.subscription) this.subscription.unsubscribe()
    clearTimeout(this.hideTimer)
    clearTimeout(this.stopTimer)
  }

  // Every keystroke lands here; the server hears "typing" at most once per
  // TYPING_THROTTLE_MS (the other side's indicator lingers a beat longer and is
  // refreshed by each beat), and "stopped" once after a pause.
  input() {
    const now = Date.now()
    if (!this.announced || now - this.lastSentAt >= TYPING_THROTTLE_MS) {
      this.lastSentAt = now
      this.announced = true
      this.sendTyping(true)
    }
    clearTimeout(this.stopTimer)
    this.stopTimer = setTimeout(() => this.stopTyping(), 1800)
  }

  stopTyping() {
    clearTimeout(this.stopTimer)
    if (!this.announced) return
    this.announced = false
    this.lastSentAt = 0
    this.sendTyping(false)
  }

  received(data) {
    if (Number(data.user_id) === this.userIdValue) return

    if (data.typing) {
      const text = this.indicatorTarget.querySelector(".typing-text")
      if (text) text.textContent = `${data.username} is typing`
      this.indicatorTarget.classList.remove("hidden")
      this.element.classList.add("is-typing")
      this.keepNewestInView()
      clearTimeout(this.hideTimer)
      this.hideTimer = setTimeout(() => this.hide(), TYPING_THROTTLE_MS + 1000)
    } else {
      this.hide()
    }
  }

  hide() {
    this.element.classList.remove("is-typing")
    if (this.hasIndicatorTarget) {
      this.indicatorTarget.classList.add("hidden")
      const text = this.indicatorTarget.querySelector(".typing-text")
      if (text) text.textContent = ""
    }
  }

  // The dots take a line under the thread; keep the newest message in view
  // for someone already reading the bottom of the chat.
  keepNewestInView() {
    const thread = document.getElementById("messages")
    if (thread && thread.scrollHeight - thread.scrollTop - thread.clientHeight < 160) {
      requestAnimationFrame(() => { thread.scrollTop = thread.scrollHeight })
    }
  }

  sendTyping(typing) {
    if (this.subscription) this.subscription.perform("typing", { typing })
  }
}
