import { Controller } from "@hotwired/stimulus"

// Alerts page: reflect reads right away instead of after a reload.
// Tapping an alert marks it read on the server as it opens, and "Mark all
// read" posts in the background; this updates the rows, the "N new updates"
// line and the bell badges at the same moment, so nothing looks stale.
export default class extends Controller {
  static targets = ["row", "sub", "markAll"]

  open(event) {
    const row = event.currentTarget
    if (!row.classList.contains("is-unread")) return
    this.markRead(row)
    this.setUnread(this.unreadCount())
  }

  markAll() {
    this.rowTargets.forEach(row => this.markRead(row))
    this.setUnread(0)
    if (this.hasMarkAllTarget) this.markAllTarget.style.display = "none"
  }

  markRead(row) {
    row.classList.remove("is-unread")
    row.querySelector(".fc-notifrow-dot")?.remove()
  }

  unreadCount() {
    return this.rowTargets.filter(row => row.classList.contains("is-unread")).length
  }

  setUnread(count) {
    if (this.hasSubTarget) {
      this.subTarget.textContent = count > 0
        ? `${count} new update${count === 1 ? "" : "s"} waiting for you.`
        : "You're all caught up. 🕊️"
    }
    if (count === 0 && this.hasMarkAllTarget) this.markAllTarget.style.display = "none"

    // Bell badge in the top bar, and the count the Android app reads for its tab badge.
    document.querySelectorAll(".fc-nav-notifications .fc-count-badge").forEach(badge => {
      if (count > 0) badge.textContent = count > 99 ? "99+" : count
      else badge.remove()
    })
    document.body.dataset.nativeUnreadNotifications = String(count)
  }
}
