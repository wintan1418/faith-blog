import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

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
    this.subscription = consumer.subscriptions.create(
      { channel: "ConversationTypingChannel", conversation_id: this.conversationIdValue },
      { received: (data) => this.received(data) }
    )
  }

  disconnect() {
    this.sendTyping(false)
    if (this.subscription) consumer.subscriptions.remove(this.subscription)
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
      this.indicatorTarget.textContent = `${data.username} is typing...`
      this.indicatorTarget.classList.remove("hidden")
      clearTimeout(this.hideTimer)
      this.hideTimer = setTimeout(() => this.hide(), 2200)
    } else {
      this.hide()
    }
  }

  hide() {
    if (this.hasIndicatorTarget) {
      this.indicatorTarget.classList.add("hidden")
      this.indicatorTarget.textContent = ""
    }
  }

  sendTyping(typing) {
    if (this.subscription) this.subscription.perform("typing", { typing })
  }
}
