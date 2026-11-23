import { Controller } from "@hotwired/stimulus"

// The "Say hello" sheet on Breathers around you. One sheet per page, filled
// from the button that opened it. Connected → a message (POST /around/hello);
// not yet → a connection request carrying the note (POST /connection_requests).
export default class extends Controller {
  static targets = ["dialog", "avatar", "name", "headline", "chips", "lines", "form", "recipient", "input", "note", "compose", "card"]
  static values = { helloUrl: { type: String, default: "/around/hello" } }

  open({ params: { person } }) {
    this.person = person
    this.opener = document.activeElement
    this.fillHeader(person)

    const card = person.mode === "card"
    this.composeTarget.hidden = card
    this.cardTarget.hidden = !card
    if (!card) this.fillCompose(person)

    this.dialogTarget.showModal()
    if (!card) this.linesTarget.querySelector("button")?.focus()
  }

  fillHeader(person) {
    this.avatarTarget.replaceChildren()
    if (person.avatar) {
      const img = document.createElement("img")
      img.src = person.avatar
      img.alt = ""
      this.avatarTarget.append(img)
      this.avatarTarget.removeAttribute("style")
    } else {
      this.avatarTarget.textContent = person.initial
      this.avatarTarget.setAttribute("style", person.tint || "")
    }
    this.nameTarget.textContent = person.name
    this.headlineTarget.textContent = person.headline || ""
    this.headlineTarget.hidden = !person.headline
    this.chipsTarget.replaceChildren(...person.chips.map((text, i) => {
      const chip = document.createElement("span")
      chip.className = `ba-chip ${i === 0 ? "is-plain" : "is-mint"}`
      chip.textContent = text
      return chip
    }))
  }

  fillCompose(person) {
    const message = person.mode === "message"
    this.formTarget.action = message ? this.helloUrlValue : person.request_url
    this.recipientTarget.value = person.id
    this.recipientTarget.disabled = !message
    this.inputTarget.name = message ? "body" : "message"
    this.formTarget.dataset.turbo = "true"
    this.noteTarget.textContent = message
      ? `You're connected, so this goes straight to your messages with ${person.name}.`
      : `Not connected yet, so this goes as a connection request with your note. ${person.name} sees it once and can accept or ignore.`

    this.linesTarget.replaceChildren(...person.lines.map((line, i) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "ba-line"
      button.setAttribute("role", "radio")
      button.setAttribute("aria-checked", String(i === 0))
      button.textContent = line
      button.addEventListener("click", () => this.choose(i))
      button.addEventListener("keydown", (event) => this.arrow(event, i))
      return button
    }))
    this.choose(0, false)
  }

  choose(index, focus = true) {
    const buttons = [...this.linesTarget.children]
    buttons.forEach((b, i) => {
      b.setAttribute("aria-checked", String(i === index))
      b.tabIndex = i === index ? 0 : -1
    })
    this.inputTarget.value = this.person.lines[index]
    if (focus) buttons[index]?.focus()
  }

  arrow(event, index) {
    const count = this.person.lines.length
    if (event.key === "ArrowDown" || event.key === "ArrowRight") { event.preventDefault(); this.choose((index + 1) % count) }
    if (event.key === "ArrowUp" || event.key === "ArrowLeft") { event.preventDefault(); this.choose((index - 1 + count) % count) }
  }

  // A request answers with a Turbo Stream (the button becomes "Request sent"); close the sheet.
  sent(event) {
    if (event.detail.success) this.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
    this.opener?.focus?.()
  }
}
