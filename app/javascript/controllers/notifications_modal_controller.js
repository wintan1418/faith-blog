import { Controller } from "@hotwired/stimulus"

// Notifications popover dialog. The bell button toggles it.
// On open, points the inner turbo-frame at /notifications/popover so
// the panel is fetched fresh each time (and notifications get marked
// read server-side as a side effect of the GET).
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    if (event) event.preventDefault()
    if (!this.hasDialogTarget) return

    const frame = this.dialogTarget.querySelector("turbo-frame#notifications_panel")
    if (frame) frame.src = "/notifications/popover"

    if (typeof this.dialogTarget.showModal === "function") {
      this.dialogTarget.showModal()
    } else {
      this.dialogTarget.setAttribute("open", "")
    }
    // Hide the unread badge on the bell button immediately so it
    // doesn't keep pulsing while the user is reading.
    document.querySelectorAll(".fc-notif-pulse-badge").forEach(b => b.remove())
  }

  close(event) {
    if (event) event.preventDefault()
    if (typeof this.dialogTarget.close === "function") {
      this.dialogTarget.close()
    } else {
      this.dialogTarget.removeAttribute("open")
    }
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
