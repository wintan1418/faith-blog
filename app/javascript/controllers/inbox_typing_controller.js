import { Controller } from "@hotwired/stimulus"
import { subscribeTyping } from "../channels/typing_hub"

// A conversation row in the inbox shows a green "typing…" while the other
// person is writing. Uses the same typing channel as the open chat; only the
// first rows listen, so a long inbox doesn't open dozens of subscriptions.
const MAX_ROWS = 30

export default class extends Controller {
  static values = { conversationId: Number, userId: Number }

  connect() {
    const siblings = this.element.parentElement ? Array.from(this.element.parentElement.children) : []
    if (siblings.indexOf(this.element) >= MAX_ROWS) return
    this.subscription = subscribeTyping(this.conversationIdValue, (data) => this.received(data))
  }

  disconnect() {
    clearTimeout(this.timer)
    if (this.subscription) this.subscription.unsubscribe()
  }

  received(data) {
    if (Number(data.user_id) === this.userIdValue) return
    clearTimeout(this.timer)
    this.element.classList.toggle("is-typing", !!data.typing)
    if (data.typing) this.timer = setTimeout(() => this.element.classList.remove("is-typing"), 2500)
  }
}
