import { Controller } from "@hotwired/stimulus"

// Copy the inviter's signup URL to the clipboard with a brief "Copied" pulse.
export default class extends Controller {
  static targets = ["input", "copyBtn"]

  async copy(event) {
    event.preventDefault()
    if (!this.hasInputTarget) return
    const text = this.inputTarget.value
    try {
      await navigator.clipboard.writeText(text)
      this.flash("✓ Copied")
    } catch {
      // Fallback for older browsers: select + execCommand
      this.inputTarget.focus()
      this.inputTarget.select()
      try { document.execCommand("copy"); this.flash("✓ Copied") }
      catch { this.flash("Couldn't copy") }
    }
  }

  flash(text) {
    if (!this.hasCopyBtnTarget) return
    const btn = this.copyBtnTarget
    const original = btn.innerHTML
    btn.innerHTML = text
    btn.disabled = true
    setTimeout(() => { btn.innerHTML = original; btn.disabled = false }, 1400)
  }
}
