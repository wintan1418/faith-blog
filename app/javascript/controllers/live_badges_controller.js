import { Controller } from "@hotwired/stimulus"

// Keeps the Messages and Notifications badges current without a refresh.
// The server replaces this element with fresh numbers when a message arrives or
// a chat is read; when the page comes back into view (phone unlocked, app
// reopened) it asks for the numbers again, since it may have missed updates.
export default class extends Controller {
  static values = { messages: Number, notifications: Number, url: String }

  connect() {
    this.apply()
    this.onVisible = () => { if (document.visibilityState === "visible") this.refresh() }
    document.addEventListener("visibilitychange", this.onVisible)
    window.addEventListener("pageshow", this.onVisible)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisible)
    window.removeEventListener("pageshow", this.onVisible)
  }

  async refresh() {
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!res.ok) return
      const { messages, notifications } = await res.json()
      const changed = messages !== this.messagesValue
      this.messagesValue = messages
      this.notificationsValue = notifications
      this.apply()
      // The inbox list itself may be stale too: reload it quietly.
      if (changed && document.getElementById("msg_rows") && window.Turbo) {
        window.Turbo.visit(window.location.href, { action: "replace" })
      }
    } catch (_) { /* offline: keep what we have */ }
  }

  apply() {
    this.setBadge(".fc-nav-inbox", this.messagesValue, "Messages", "unread")
    this.setBadge(".fc-nav-notifications", this.notificationsValue, "Notifications", "new")
    const body = document.body
    if ("nativeUnreadMessages" in body.dataset) body.dataset.nativeUnreadMessages = String(this.messagesValue)
    if ("nativeUnreadNotifications" in body.dataset) body.dataset.nativeUnreadNotifications = String(this.notificationsValue)
  }

  setBadge(selector, count, label, word) {
    document.querySelectorAll(selector).forEach(button => {
      let badge = button.querySelector(".fc-count-badge")
      if (count > 0) {
        if (!badge) {
          badge = document.createElement("span")
          badge.className = "fc-count-badge eg-badge"
          badge.setAttribute("aria-hidden", "true")
          button.appendChild(badge)
        }
        badge.textContent = count > 99 ? "99+" : String(count)
        button.setAttribute("aria-label", `${label}, ${count} ${word}`)
      } else {
        badge?.remove()
        button.setAttribute("aria-label", label)
      }
    })
  }
}
