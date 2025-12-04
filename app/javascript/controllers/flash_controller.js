import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message"]

  connect() {
    // Auto-dismiss after 5 seconds
    this.timeout = setTimeout(() => {
      this.dismiss()
    }, 5000)
  }

  dismiss() {
    this.element.classList.add("opacity-0", "translate-x-4")
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }
}

