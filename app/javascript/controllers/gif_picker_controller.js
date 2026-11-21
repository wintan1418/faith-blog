import { Controller } from "@hotwired/stimulus"
import { loadGifPanel } from "../lazy_libs"

// The GIF button in the chat composer and the comment boxes. The picker itself
// (search, grid, states) loads on first open. Picking a GIF fills hidden
// fields on the surrounding form and sends it straight away.
export default class extends Controller {
  static targets = ["button", "popover"]
  static values = { scope: String, searchUrl: String, trendingUrl: String }

  connect() {
    this.open = false
    this.onOutside = (event) => { if (this.open && !this.element.contains(event.target)) this.hide() }
    this.onKey = (event) => { if (this.open && event.key === "Escape") { event.preventDefault(); this.hide(); this.buttonTarget.focus() } }
    this.onSubmitEnd = () => this.clearFields()
    this.form()?.addEventListener("turbo:submit-end", this.onSubmitEnd)
  }

  disconnect() {
    this.hide()
    this.form()?.removeEventListener("turbo:submit-end", this.onSubmitEnd)
    this.panel?.destroy()
  }

  async toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.open ? this.hide() : await this.show()
  }

  async show() {
    this.closeEmojiPicker()
    this.open = true
    this.popoverTarget.classList.remove("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.freeSheet()
    document.addEventListener("click", this.onOutside)
    document.addEventListener("keydown", this.onKey)

    if (!this.panel) {
      this.popoverTarget.innerHTML = '<p class="gif-state">Loading GIFs…</p>'
      try {
        const { GifPanel } = await loadGifPanel()
        if (!this.open || !this.element.isConnected) return
        this.panel = new GifPanel(this.popoverTarget, {
          searchUrl: this.searchUrlValue,
          trendingUrl: this.trendingUrlValue,
          onPick: (gif) => this.pick(gif)
        })
      } catch (_e) {
        this.popoverTarget.innerHTML = '<p class="gif-state is-error">GIFs couldn\'t load. Check your connection and try again.</p>'
        return
      }
    }
    this.panel.opened()
  }

  hide() {
    if (!this.hasPopoverTarget) return
    this.open = false
    this.popoverTarget.classList.add("hidden")
    this.buttonTarget?.setAttribute("aria-expanded", "false")
    this.unfreeSheet()
    document.removeEventListener("click", this.onOutside)
    document.removeEventListener("keydown", this.onKey)
  }

  pick(gif) {
    const form = this.form()
    if (!form) return
    this.clearFields()
    const fields = { gif_url: gif.url, gif_width: gif.width, gif_height: gif.height, gif_title: gif.title }
    for (const [name, value] of Object.entries(fields)) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = `${this.scopeValue}[${name}]`
      input.value = value ?? ""
      input.dataset.gifField = ""
      form.appendChild(input)
    }
    this.hide()
    form.requestSubmit()
  }

  clearFields() {
    this.form()?.querySelectorAll("input[data-gif-field]").forEach((input) => input.remove())
  }

  form() {
    return this.element.closest("form")
  }

  // One picker at a time: close the emoji picker in the same box.
  closeEmojiPicker() {
    const host = this.element.closest("[data-controller~='emoji-picker']")
    if (!host) return
    const emoji = this.application.getControllerForElementAndIdentifier(host, "emoji-picker")
    if (emoji?.pickerVisible) emoji.hide()
  }

  // On phones the comment picker is a sheet pinned to the bottom of the
  // screen. position: fixed is trapped by a transformed ancestor (cards lift
  // on hover), so switch those effects off while it's open, as the emoji
  // picker does.
  freeSheet() {
    this.unfreeSheet()
    if (getComputedStyle(this.popoverTarget).position !== "fixed") return
    for (let el = this.popoverTarget.parentElement; el && el !== document.documentElement; el = el.parentElement) {
      const style = getComputedStyle(el)
      if (style.transform !== "none" || style.filter !== "none" ||
          (style.backdropFilter && style.backdropFilter !== "none") ||
          /paint|layout|strict|content/.test(style.contain || "")) {
        el.classList.add("fc-emoji-sheet-host")
        this.hosts.push(el)
      }
    }
  }

  unfreeSheet() {
    (this.hosts || []).forEach((el) => el.classList.remove("fc-emoji-sheet-host"))
    this.hosts = []
  }
}
