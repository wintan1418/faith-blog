import { Controller } from "@hotwired/stimulus"

// The composer's "Post as" switch: you, or a page you help run. Swaps the
// face and name at the top and turns off "Post anonymously" for a page.
export default class extends Controller {
  static targets = ["select", "avatar", "name", "anonymous", "anonymousRow"]

  connect() {
    this.change()
  }

  change() {
    if (!this.hasSelectTarget) return
    const option = this.selectTarget.selectedOptions[0]
    if (!option) return
    const asPage = this.selectTarget.value !== ""
    if (this.hasNameTarget) this.nameTarget.textContent = option.dataset.name || option.textContent
    if (this.hasAvatarTarget) {
      this.avatarTargets.forEach((avatar) => { avatar.hidden = avatar.dataset.identity !== this.selectTarget.value })
    }
    if (this.hasAnonymousTarget) {
      if (asPage) this.anonymousTarget.checked = false
      this.anonymousTarget.disabled = asPage
    }
    if (this.hasAnonymousRowTarget) this.anonymousRowTarget.hidden = asPage
  }
}
