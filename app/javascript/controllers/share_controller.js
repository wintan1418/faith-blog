import { Controller } from "@hotwired/stimulus"
import { flipIfNoRoomAbove } from "../menu_flip"

// The card renderer and sheet load the first time someone opens them.
let sheetModule
const loadShareSheet = () => (sheetModule ||= import("../share/share_sheet").catch((error) => { sheetModule = null; throw error }))

export default class extends Controller {
  static values = {
    url:         String,
    title:       String,
    author:      String,
    snippet:     String,
    // A breath's card data (ShareCardsController). Menus without one (a
    // series) still get a card, drawn from the values below.
    cardUrl:     String,
    image:       String,
    accent:      { type: String, default: "#34d399" },
    accentDeep:  { type: String, default: "#10b981" }
  }

  static targets = ["menu", "toast", "nativeItem", "webItem"]

  // The Android app (1.0.7+) gives us its share sheet; the plain WebView has none.
  get native() { return window.BrethreignNative }
  get inApp() { return /Hotwire Native|Turbo Native/.test(navigator.userAgent) }

  connect() {
    if (this.native) {
      this.nativeItemTargets.forEach(el => el.classList.remove("hidden"))
      this.webItemTargets.forEach(el => el.classList.add("hidden"))
    }
    this.boundEsc = this.onEsc.bind(this)
    this.boundOutsideClick = this.outsideClick.bind(this)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundEsc)
    document.removeEventListener("mousedown", this.boundOutsideClick, true)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasMenuTarget) return

    if (this.menuTarget.classList.contains("hidden")) {
      this.show()
    } else {
      this.hide()
    }
  }

  show() {
    this.menuTarget.classList.remove("hidden")
    flipIfNoRoomAbove(this.menuTarget)
    // Capture-phase mousedown so we beat any stopPropagation deeper in the tree.
    document.addEventListener("mousedown", this.boundOutsideClick, true)
    document.addEventListener("keydown", this.boundEsc)
  }

  hide() {
    if (this.hasMenuTarget) this.menuTarget.classList.add("hidden")
    document.removeEventListener("mousedown", this.boundOutsideClick, true)
    document.removeEventListener("keydown", this.boundEsc)
  }

  outsideClick(event) {
    if (!this.element.contains(event.target)) this.hide()
  }

  onEsc(event) {
    if (event.key === "Escape") this.hide()
  }

  shareText() { return `${this.titleValue} — ${this.urlValue}` }

  // Phone share sheet: WhatsApp, X, Instagram, Telegram, email…
  nativeShare(event) {
    event.preventDefault()
    this.native?.share(this.shareText(), this.titleValue)
    this.hide()
  }

  async copyLink(event) {
    event.preventDefault()
    this.hide()
    if (this.native) { this.native.copy(this.urlValue); return }
    try {
      await navigator.clipboard.writeText(this.urlValue)
      this.flash("Link copied")
    } catch {
      // Older app versions: the WebView may refuse the clipboard API.
      const field = Object.assign(document.createElement("textarea"), { value: this.urlValue })
      field.style.cssText = "position:fixed;opacity:0"
      document.body.appendChild(field)
      field.select()
      const ok = document.execCommand("copy")
      field.remove()
      this.flash(ok ? "Link copied" : "Could not copy", !ok)
    }
  }

  // In the app a new window can't open, so go to the link directly instead.
  openExternal(url) {
    if (this.inApp) window.location.href = url
    else window.open(url, "_blank", "noopener")
  }

  whatsapp(event) {
    event.preventDefault()
    this.openExternal(`https://api.whatsapp.com/send?text=${encodeURIComponent(this.shareText())}`)
    this.hide()
  }

  twitter(event) {
    event.preventDefault()
    const params = new URLSearchParams({ text: this.titleValue, url: this.urlValue })
    this.openExternal(`https://twitter.com/intent/tweet?${params.toString()}`)
    this.hide()
  }

  email(event) {
    event.preventDefault()
    const subject = encodeURIComponent(this.titleValue)
    const body = encodeURIComponent(`${this.snippetValue}\n\n${this.urlValue}`)
    window.location.href = `mailto:?subject=${subject}&body=${body}`
    this.hide()
  }

  linkedin(event) {
    event.preventDefault()
    this.openExternal(`https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(this.urlValue)}`)
    this.hide()
  }

  // "Snapshot for status": a designed card image (Story / Square / Portrait).
  snapshot(event) {
    event.preventDefault()
    this.openSheet("image")
  }

  // The breath and its best replies, one card each.
  shareThread(event) {
    event.preventDefault()
    this.openSheet("thread")
  }

  async openSheet(mode) {
    this.hide()
    try {
      const { openShareSheet } = await loadShareSheet()
      const source = this.cardUrlValue ? { cardUrl: this.cardUrlValue } : { data: this.cardFromValues() }
      openShareSheet({ ...source, mode: this.cardUrlValue ? mode : "image", flash: (text, error) => this.flash(text, error) })
    } catch (err) {
      console.error("Share sheet failed to load", err)
      this.flash("Couldn't open the image sheet. Check your connection.", true)
    }
  }

  // A card for a share menu without card data (e.g. a series): its title,
  // words and link. The QR code is fetched for the link when the sheet opens.
  cardFromValues() {
    const author = this.authorValue || "anonymous"
    const anonymous = author === "anonymous"
    let label = this.urlValue
    try {
      const url = new URL(this.urlValue, window.location.origin)
      label = `${url.host.replace(/^www\./, "")}${url.pathname}`
    } catch { /* keep the raw address */ }
    return {
      id: "share",
      link: this.urlValue,
      link_label: label,
      qr: null,
      accent: this.accentValue,
      accent_deep: this.accentDeepValue,
      author: anonymous ? { anonymous: true, name: "Anonymous" } : { anonymous: false, name: author, username: author, initial: author.charAt(0).toUpperCase() },
      title: this.titleValue,
      text: this.snippetValue,
      truncated: false,
      image: this.imageValue ? { fallback: this.imageValue } : null,
      counts: null,
      date: "",
      label: null,
      series: null,
      share_text: this.shareText()
    }
  }

  flash(text, error = false) {
    if (!this.hasToastTarget) return
    this.toastTarget.textContent = text
    this.toastTarget.classList.remove("hidden", "is-error")
    if (error) this.toastTarget.classList.add("is-error")
    clearTimeout(this._toastTimer)
    this._toastTimer = setTimeout(() => this.toastTarget.classList.add("hidden"), 2400)
  }
}
