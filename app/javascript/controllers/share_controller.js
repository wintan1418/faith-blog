import { Controller } from "@hotwired/stimulus"
import html2canvas from "html2canvas"

// Share menu for a single breath.
// Expects on the controller element:
//   data-share-url-value      = absolute URL to the breath
//   data-share-title-value    = title of the breath
//   data-share-author-value   = display name of the author
//   data-share-snippet-value  = short text snippet
//   data-share-image-value    = (optional) absolute URL to the cover image
export default class extends Controller {
  static values = {
    url:     String,
    title:   String,
    author:  String,
    snippet: String,
    image:   String
  }

  static targets = ["menu", "toast"]

  connect() {
    this.boundOutsideClick = this.outsideClick.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutsideClick)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasMenuTarget) return

    const visible = !this.menuTarget.classList.contains("hidden")
    if (visible) {
      this.hide()
    } else {
      this.show()
    }
  }

  show() {
    this.menuTarget.classList.remove("hidden")
    setTimeout(() => document.addEventListener("click", this.boundOutsideClick), 50)
  }

  hide() {
    this.menuTarget.classList.add("hidden")
    document.removeEventListener("click", this.boundOutsideClick)
  }

  outsideClick(event) {
    if (!this.element.contains(event.target)) this.hide()
  }

  async copyLink(event) {
    event.preventDefault()
    try {
      await navigator.clipboard.writeText(this.urlValue)
      this.flash("Link copied")
    } catch {
      this.flash("Could not copy", true)
    }
    this.hide()
  }

  whatsapp(event) {
    event.preventDefault()
    const text = `${this.titleValue} — ${this.urlValue}`
    window.open(`https://api.whatsapp.com/send?text=${encodeURIComponent(text)}`, "_blank", "noopener")
    this.hide()
  }

  twitter(event) {
    event.preventDefault()
    const params = new URLSearchParams({ text: this.titleValue, url: this.urlValue })
    window.open(`https://twitter.com/intent/tweet?${params.toString()}`, "_blank", "noopener")
    this.hide()
  }

  email(event) {
    event.preventDefault()
    const subject = encodeURIComponent(this.titleValue)
    const body = encodeURIComponent(`${this.snippetValue}\n\n${this.urlValue}`)
    window.location.href = `mailto:?subject=${subject}&body=${body}`
    this.hide()
  }

  async snapshot(event) {
    event.preventDefault()
    this.flash("Rendering snapshot...")

    const node = this.buildSnapshotNode()
    document.body.appendChild(node)

    try {
      const canvas = await html2canvas(node, {
        backgroundColor: null,
        scale: 2,
        useCORS: true,
        logging: false
      })
      const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"))
      const url = URL.createObjectURL(blob)

      const a = document.createElement("a")
      a.href = url
      a.download = `breath-${Date.now()}.png`
      document.body.appendChild(a)
      a.click()
      a.remove()
      URL.revokeObjectURL(url)

      this.flash("Saved to your downloads")
    } catch (err) {
      console.error(err)
      this.flash("Snapshot failed", true)
    } finally {
      node.remove()
      this.hide()
    }
  }

  buildSnapshotNode() {
    const wrap = document.createElement("div")
    wrap.style.cssText = `
      position: fixed; top: -9999px; left: -9999px;
      width: 1080px; height: 1350px;
      background: linear-gradient(160deg, #0b0f10 0%, #111a18 60%, #0e1f1a 100%);
      color: #f4faf7;
      font-family: 'Source Sans 3', -apple-system, BlinkMacSystemFont, sans-serif;
      padding: 80px 80px 100px;
      box-sizing: border-box;
      display: flex; flex-direction: column; justify-content: space-between;
    `

    const safe = (s) => (s || "").replace(/[<>]/g, "")

    wrap.innerHTML = `
      <div>
        <div style="display:flex;align-items:center;gap:14px;font-weight:800;letter-spacing:-0.01em;">
          <div style="width:44px;height:44px;border-radius:12px;background:#34d399;display:grid;place-items:center;color:#042f1d;font-weight:900;">B</div>
          <div style="font-size:22px;color:#c8d3cf;">Faith Community</div>
        </div>
        <div style="margin-top:90px;font-size:18px;font-weight:700;letter-spacing:0.18em;text-transform:uppercase;color:#34d399;">A Breath</div>
        <h1 style="margin:18px 0 0;font-size:64px;line-height:1.1;letter-spacing:-0.02em;font-weight:900;">
          ${safe(this.titleValue)}
        </h1>
        <p style="margin-top:36px;font-size:30px;line-height:1.45;color:#c8d3cf;font-weight:400;">
          ${safe(this.snippetValue)}
        </p>
      </div>
      <div style="display:flex;align-items:center;justify-content:space-between;border-top:1px solid rgba(255,255,255,0.10);padding-top:28px;">
        <div style="display:flex;align-items:center;gap:14px;">
          <div style="width:48px;height:48px;border-radius:50%;background:#34d399;color:#042f1d;display:grid;place-items:center;font-weight:900;font-size:22px;">
            ${safe((this.authorValue || "?").charAt(0).toUpperCase())}
          </div>
          <div>
            <div style="font-weight:800;font-size:24px;">@${safe(this.authorValue || "anonymous")}</div>
            <div style="color:#8a9893;font-size:18px;">read more on Faith Community</div>
          </div>
        </div>
        <div style="font-size:18px;color:#8a9893;font-weight:700;">Tap to read →</div>
      </div>
    `
    return wrap
  }

  flash(text, error = false) {
    if (!this.hasToastTarget) return
    this.toastTarget.textContent = text
    this.toastTarget.classList.remove("hidden", "is-error")
    if (error) this.toastTarget.classList.add("is-error")
    clearTimeout(this._toastTimer)
    this._toastTimer = setTimeout(() => this.toastTarget.classList.add("hidden"), 2000)
  }
}
