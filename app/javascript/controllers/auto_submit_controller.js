import { Controller } from "@hotwired/stimulus"

// Sends its form as soon as a choice changes (e.g. a team member's role).
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
