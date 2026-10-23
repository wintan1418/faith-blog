import { Controller } from "@hotwired/stimulus"

// Shows a server time in the reader's own time zone (the server runs on UTC).
// <time datetime="ISO" data-controller="local-time" data-local-time-format-value="time|short|inbox|day">
export default class extends Controller {
  static values = { format: { type: String, default: "time" } }

  connect() {
    const date = new Date(this.element.getAttribute("datetime"))
    if (isNaN(date)) return
    this.element.textContent = this.format(date)
  }

  format(date) {
    const now = new Date()
    const time = (opts = {}) => date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit", ...opts })
    const sameDay = (a, b) => a.toDateString() === b.toDateString()
    const daysAgo = Math.floor((startOfDay(now) - startOfDay(date)) / 86400000)

    switch (this.formatValue) {
      case "short":
        return time().replace(/\s?[AP]M$/i, "")
      case "inbox":
        if (sameDay(date, now)) return time()
        if (daysAgo < 7) return date.toLocaleDateString([], { weekday: "short" })
        if (date.getFullYear() === now.getFullYear()) return date.toLocaleDateString([], { month: "short", day: "numeric" })
        return date.toLocaleDateString([], { month: "short", day: "numeric", year: "numeric" })
      case "day":
        if (daysAgo === 0) return "Today"
        if (daysAgo === 1) return "Yesterday"
        if (daysAgo < 7) return date.toLocaleDateString([], { weekday: "long" })
        if (date.getFullYear() === now.getFullYear()) return date.toLocaleDateString([], { month: "long", day: "numeric" })
        return date.toLocaleDateString([], { month: "long", day: "numeric", year: "numeric" })
      default:
        return time()
    }
  }
}

function startOfDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
