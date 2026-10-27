import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form"]

  toggle() {
    this.formTarget.classList.toggle("hidden")
    
    if (!this.formTarget.classList.contains("hidden")) {
      const textarea = this.formTarget.querySelector("textarea")
      if (textarea) {
        textarea.focus()
        // Start typing after a prefilled "@name ".
        const end = textarea.value.length
        textarea.setSelectionRange(end, end)
      }
    }
  }
}

