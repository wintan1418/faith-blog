import { Controller } from "@hotwired/stimulus"

// Going back to a page (and, in the app, returning to a screen) shows Turbo's
// saved copy of it, not a fresh one. A <turbo-frame> with this controller
// reloads itself from `url` when it's shown from such a copy, so things that
// changed meanwhile (e.g. a getting-started step done on another page) show.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.markStale = () => this.element.setAttribute("data-stale", "")
    document.addEventListener("turbo:before-cache", this.markStale)

    const preview = document.documentElement.hasAttribute("data-turbo-preview") // a fresh copy is on its way
    if (this.element.hasAttribute("data-stale") && !preview) {
      this.element.removeAttribute("data-stale")
      this.reload()
    }
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.markStale)
  }

  reload() {
    if (!this.urlValue) return
    if (this.element.getAttribute("src")) this.element.reload()
    else this.element.src = this.urlValue
  }
}
