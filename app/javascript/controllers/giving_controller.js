import { Controller } from "@hotwired/stimulus"

// /give: amount chips, currency switch and the button label.
export default class extends Controller {
  static targets = ["chips", "amount", "symbol", "hint", "submit", "submitLabel"]
  static values = { currencies: Object }

  connect() { this.update() }

  get currency() { return this.element.querySelector("input[name='donation[currency]']:checked")?.value || "NGN" }
  get config() { return this.currenciesValue[this.currency] }
  get monthly() { return this.element.querySelector("input[name='donation[frequency]']:checked")?.value === "monthly" }

  pick(event) {
    this.amountTarget.value = event.currentTarget.dataset.amount
    this.update()
  }

  typed() { this.update() }

  switchCurrency() {
    const { symbol, presets, min } = this.config
    this.chipsTarget.innerHTML = presets.map((amt, i) =>
      `<button type="button" class="give-chip${i === 1 ? " is-on" : ""}" data-action="giving#pick" data-amount="${amt}">${symbol}${amt.toLocaleString()}</button>`).join("")
    this.symbolTarget.textContent = symbol
    this.amountTarget.min = min
    this.amountTarget.value = presets[1]
    this.hintTarget.textContent = `Minimum ${symbol}${min.toLocaleString()}`
    this.update()
  }

  update() {
    const { symbol } = this.config
    const amount = Number(this.amountTarget.value)
    this.chipsTarget.querySelectorAll(".give-chip").forEach((chip) =>
      chip.classList.toggle("is-on", Number(chip.dataset.amount) === amount))
    if (this.submitTarget.disabled) return
    const shown = amount > 0 ? `${symbol}${amount.toLocaleString()}` : ""
    this.submitLabelTarget.textContent = shown ? `Give ${shown}${this.monthly ? " monthly" : ""}` : "Give"
  }
}
