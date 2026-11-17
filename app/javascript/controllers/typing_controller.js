import { Controller } from "@hotwired/stimulus"
import { subscribeTyping } from "../channels/typing_hub"

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
    this.subscription = subscribeTyping(this.conversationIdValue, (data) => this.received(data))
  }

  disconnect() {
    this.sendTyping(false)
    if (this.subscription) this.subscription.unsubscribe()
    clearTimeout(this.hideTimer)
    clearTimeout(this.stopTimer)
  }

  input() {
    this.sendTyping(true)
    clearTimeout(this.stopTimer)
    this.stopTimer = setTimeout(() => this.sendTyping(false), 1800)
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
      this.hideTimer = setTimeout(() => this.hide(), 2200)
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
