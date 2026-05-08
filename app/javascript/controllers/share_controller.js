import { Controller } from "@hotwired/stimulus"
import html2canvas from "html2canvas"

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
    this.hide()
    this.flash("Rendering snapshot...")

    const node = this.buildSnapshotNode()
    document.body.appendChild(node)

    try {
      // Give the browser one frame to lay out fonts before capturing.
      await new Promise(r => requestAnimationFrame(() => r()))

      const canvas = await html2canvas(node, {
        backgroundColor: "#0b0f10",
        scale: 2,
        useCORS: true,
        logging: false,
        windowWidth: 1080,
        windowHeight: 1350
      })

      const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"))
      if (!blob) throw new Error("toBlob returned null")

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
      console.error("Snapshot error:", err)
      this.flash(`Snapshot failed: ${err.message || err}`, true)
    } finally {
      node.remove()
    }
  }

  buildSnapshotNode() {
    const wrap = document.createElement("div")
    wrap.style.cssText = `
      position: fixed; top: 0; left: 0;
      width: 1080px; height: 1350px;
      transform: translate(-200vw, 0);
      background: linear-gradient(160deg, #0b0f10 0%, #111a18 60%, #0e1f1a 100%);
      color: #f4faf7;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      padding: 80px 80px 100px;
      box-sizing: border-box;
      display: flex; flex-direction: column; justify-content: space-between;
    `

    const safe = (s) => (s || "").replace(/[<>]/g, "")
    const title   = safe(this.titleValue)
    const snippet = safe(this.snippetValue)

    // Scale the body font so longer breaths still fit a single 1080×1350 frame
    // without overflowing. Numbers chosen empirically against ~920px line width.
    const len = snippet.length
    const bodyFont = len > 1100 ? 22 : len > 700 ? 26 : len > 400 ? 30 : 34
    const bodyLine = bodyFont >= 30 ? 1.45 : 1.4
    const titleFont = title ? (title.length > 60 ? 48 : 64) : 0

    const titleBlock = title
      ? `<h1 style="margin:18px 0 0;font-size:${titleFont}px;line-height:1.1;font-weight:900;color:#ffffff;">${title}</h1>`
      : ""
    const headerSpacing = title ? 90 : 60
    const bodyTopMargin = title ? 36 : 28

    wrap.innerHTML = `
      <div>
        <div style="display:flex;align-items:center;gap:14px;font-weight:800;">
          <div style="width:48px;height:48px;border-radius:12px;background:#34d399;display:flex;align-items:center;justify-content:center;color:#042f1d;font-weight:900;font-size:24px;">B</div>
          <div style="font-size:24px;color:#c8d3cf;">Faith Community</div>
        </div>
        <div style="margin-top:${headerSpacing}px;font-size:18px;font-weight:800;letter-spacing:0.2em;text-transform:uppercase;color:#34d399;">A Breath</div>
        ${titleBlock}
        <p style="margin-top:${bodyTopMargin}px;font-size:${bodyFont}px;line-height:${bodyLine};color:#c8d3cf;font-weight:400;white-space:pre-wrap;">${snippet}</p>
      </div>
      <div style="display:flex;align-items:center;justify-content:space-between;border-top:1px solid rgba(255,255,255,0.10);padding-top:28px;">
        <div style="display:flex;align-items:center;gap:14px;">
          <div style="width:52px;height:52px;border-radius:50%;background:#34d399;color:#042f1d;display:flex;align-items:center;justify-content:center;font-weight:900;font-size:24px;">
            ${safe((this.authorValue || "?").charAt(0).toUpperCase())}
          </div>
          <div>
            <div style="font-weight:800;font-size:24px;color:#ffffff;">@${safe(this.authorValue || "anonymous")}</div>
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
    this._toastTimer = setTimeout(() => this.toastTarget.classList.add("hidden"), 2400)
  }
}
