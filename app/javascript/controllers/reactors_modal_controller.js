import { Controller } from "@hotwired/stimulus"

// Shared "who reacted" dialog. A reaction-count button anywhere on the page
// carries the breath's reactions URL as an action param; opening points the
// inner turbo-frame at that URL so the list is fetched fresh each time.
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    if (event) event.preventDefault()
    if (!this.hasDialogTarget) return

    const url = event?.params?.url
    if (!url) return

    const frame = this.dialogTarget.querySelector("turbo-frame#reactors_panel")
    if (frame) frame.src = url

    if (typeof this.dialogTarget.showModal === "function") {
      this.dialogTarget.showModal()
    } else {
      this.dialogTarget.setAttribute("open", "")
    }
  }

  close(event) {
    if (event) event.preventDefault()
    if (!this.hasDialogTarget) return

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
