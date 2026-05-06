import { Controller } from "@hotwired/stimulus"

// Click → if the linked turbo-frame is empty, fetch the inline thread
// and reveal it. Click again → collapse.
export default class extends Controller {
  static values = { url: String, frame: String }

  toggle(event) {
    event.preventDefault()
    const frame = document.getElementById(this.frameValue)
    if (!frame) return

    const isHidden = frame.classList.contains("hidden")
    if (isHidden) {
      if (!frame.src && !frame.hasAttribute("complete")) {
        frame.src = this.urlValue
      }
      frame.classList.remove("hidden")
      // Focus the reply input once the frame finishes loading.
      const onLoad = () => {
        frame.removeEventListener("turbo:frame-load", onLoad)
        const editor = frame.querySelector("trix-editor")
        if (editor) editor.focus()
      }
      frame.addEventListener("turbo:frame-load", onLoad)
    } else {
      frame.classList.add("hidden")
    }
  }
}
