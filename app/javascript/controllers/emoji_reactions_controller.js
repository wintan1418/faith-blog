import { Controller } from "@hotwired/stimulus"
import "emoji-picker-element"

// Pop emoji picker, send the chosen emoji to /likes via fetch.
// On success, reload the page (or replace the reactions partial) so
// counts and "is-mine" state refresh.
export default class extends Controller {
  static targets = ["picker"]
  static values  = { url: String, token: String }

  connect() {
    this.boundOutsideClick = this.outsideClick.bind(this)
    if (this.hasPickerTarget) {
      const inner = this.pickerTarget.querySelector("emoji-picker")
      if (inner && !inner._wired) {
        inner.addEventListener("emoji-click", e => this.choose(e.detail.unicode))
        inner._wired = true
      }
    }
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutsideClick)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasPickerTarget) return

    const visible = !this.pickerTarget.classList.contains("hidden")
    if (visible) {
      this.hide()
    } else {
      this.show()
    }
  }

  show() {
    this.pickerTarget.classList.remove("hidden")
    setTimeout(() => document.addEventListener("click", this.boundOutsideClick), 50)
  }

  hide() {
    this.pickerTarget.classList.add("hidden")
    document.removeEventListener("click", this.boundOutsideClick)
  }

  outsideClick(event) {
    if (!this.element.contains(event.target)) this.hide()
  }

  async choose(emoji) {
    this.hide()

    const form = new FormData()
    form.set("authenticity_token", this.tokenValue)
    form.set("reaction_emoji", emoji)

    try {
      // urlValue already carries likeable_type/id as query params; preserve them.
      const response = await fetch(this.urlValue, {
        method: "POST",
        body: form,
        headers: { "Accept": "text/html" },
        credentials: "same-origin"
      })
      if (response.ok || response.redirected) {
        window.location.reload()
      } else {
        console.error("Reaction failed:", response.status, await response.text())
      }
    } catch (err) {
      console.error(err)
    }
  }
}
