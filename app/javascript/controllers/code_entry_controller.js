import { Controller } from "@hotwired/stimulus"

// The six-digit code screens (verify email, "Is this you?", two-step login):
// keeps the box to digits, sends the form once six are typed (or pasted, or
// filled in by the phone's one-time-code autofill), and counts down the
// "Send a new code" wait.
export default class extends Controller {
  static targets = ["input", "form", "resend", "countdown", "recovery"]
  static values = { cooldown: Number, autoSubmit: { type: Boolean, default: true } }

  connect() {
    this.submitted = false
    if (this.cooldownValue > 0 && this.hasResendTarget) this.startCountdown(this.cooldownValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  typed() {
    const input = this.inputTarget
    const digits = input.value.replace(/\D/g, "").slice(0, 6)
    if (input.value !== digits) input.value = digits
    if (!this.autoSubmitValue || digits.length !== 6 || this.submitted) return
    if (this.hasRecoveryTarget && this.recoveryTarget.value.trim() !== "") return

    this.submitted = true
    const form = this.hasFormTarget ? this.formTarget : input.form
    form?.requestSubmit()
  }

  // Using a recovery code: the app-code box is no longer required.
  recoveryToggled(event) {
    if (!this.hasInputTarget) return
    const open = event.target.open
    this.inputTarget.required = !open
    if (open && this.hasRecoveryTarget) this.recoveryTarget.focus()
  }

  startCountdown(seconds) {
    let left = seconds
    const button = this.resendTarget
    button.disabled = true
    const tick = () => {
      if (left <= 0) {
        clearInterval(this.timer)
        button.disabled = false
        if (this.hasCountdownTarget) this.countdownTarget.textContent = ""
        return
      }
      if (this.hasCountdownTarget) this.countdownTarget.textContent = ` in ${left}s`
      left -= 1
    }
    tick()
    this.timer = setInterval(tick, 1000)
  }
}
