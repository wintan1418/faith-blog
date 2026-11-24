import { Controller } from "@hotwired/stimulus"

// Search filters apply as soon as one changes (a GET form, so the URL holds
// them and the page can be shared).
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
