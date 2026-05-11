import { Controller } from "@hotwired/stimulus"

// First-run welcome card. Hides itself if the user dismissed it previously
// (localStorage). Server-side, the card only renders for genuinely-new users
// (no posts, no follows), so it naturally stops appearing once they engage.
export default class extends Controller {
  static values = { key: String }

  connect() {
    const key = this.keyValue || "fc:onboard"
    if (localStorage.getItem(key) === "1") {
      this.element.style.display = "none"
    }
  }

  dismiss() {
    const key = this.keyValue || "fc:onboard"
    localStorage.setItem(key, "1")
    this.element.style.display = "none"
  }
}
