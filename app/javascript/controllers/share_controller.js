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
    this.openProgress("Preparing snapshot…", "Laying out your breath at 1080×1350")

    const node = this.buildSnapshotNode()
    document.body.appendChild(node)

    try {
      // Give the browser two frames so the overlay paints and the snapshot
      // node lays out fonts before we hand the main thread to html2canvas.
      await this.nextFrame()
      await this.nextFrame()

      // If the post has an image, wait for it to actually decode before we
      // capture — otherwise html2canvas snapshots an empty box. Hard-cap
      // the wait so a missing/blocked image can't stall the whole share.
      const img = node.querySelector("img")
      if (img && !img.complete) {
        this.updateProgress("Loading attachment…", "Waiting for the image to decode")
        await new Promise((resolve) => {
          const t = setTimeout(resolve, 4000)
          img.onload  = () => { clearTimeout(t); resolve() }
          img.onerror = () => { clearTimeout(t); resolve() }
        })
      }

      this.updateProgress("Rendering image…", "This can take a few seconds")
      // One more frame so the "Rendering" text is on screen before html2canvas
      // takes over the main thread.
      await this.nextFrame()

      const canvas = await html2canvas(node, {
        backgroundColor: "#0b0f10",
        scale: 1,
        useCORS: true,
        logging: false,
        imageTimeout: 4000,
        windowWidth: 1080,
        windowHeight: 1350
      })

      this.updateProgress("Saving file…", "Almost done")
      await this.nextFrame()

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

      this.closeProgress()
      this.flash("Saved to your downloads")
    } catch (err) {
      console.error("Snapshot error:", err)
      this.closeProgress()
      this.flash(`Snapshot failed: ${err.message || err}`, true)
    } finally {
      node.remove()
    }
  }

  nextFrame() {
    return new Promise(r => requestAnimationFrame(() => r()))
  }

  openProgress(title, detail) {
    let overlay = document.getElementById("fc-snapshot-overlay")
    if (!overlay) {
      overlay = document.createElement("div")
      overlay.id = "fc-snapshot-overlay"
      overlay.className = "fc-snapshot-overlay"
      overlay.innerHTML = `
        <div class="fc-snapshot-card" role="dialog" aria-live="polite" aria-busy="true">
          <div class="fc-snapshot-spinner" aria-hidden="true"></div>
          <div class="fc-snapshot-title">${title}</div>
          <div class="fc-snapshot-detail">${detail}</div>
        </div>
      `
      document.body.appendChild(overlay)
    } else {
      this.updateProgress(title, detail)
      overlay.classList.remove("is-hidden")
    }
  }

  updateProgress(title, detail) {
    const overlay = document.getElementById("fc-snapshot-overlay")
    if (!overlay) return
    const t = overlay.querySelector(".fc-snapshot-title")
    const d = overlay.querySelector(".fc-snapshot-detail")
    if (t) t.textContent = title
    if (d) d.textContent = detail
  }

  closeProgress() {
    const overlay = document.getElementById("fc-snapshot-overlay")
    if (overlay) overlay.remove()
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
      padding: 72px 72px 88px;
      box-sizing: border-box;
      display: flex; flex-direction: column; gap: 28px;
    `

    const safe = (s) => (s || "").replace(/[<>]/g, "")
    const title   = safe(this.titleValue)
    const snippet = safe(this.snippetValue)
    const author  = safe(this.authorValue || "anonymous")
    const hasImage = !!(this.imageValue && this.imageValue.length > 1)

    // Scale the body font so longer breaths still fit a single 1080×1350 frame
    // without overflowing. Tighter ramp when an image takes ~460px of vertical.
    const len = snippet.length
    let bodyFont, bodyLine
    if (hasImage) {
      bodyFont = len > 700 ? 22 : len > 400 ? 26 : len > 200 ? 28 : 30
      bodyLine = 1.4
    } else {
      bodyFont = len > 1100 ? 22 : len > 700 ? 26 : len > 400 ? 30 : 34
      bodyLine = bodyFont >= 30 ? 1.45 : 1.4
    }
    const titleFont = title ? (title.length > 60 ? 44 : 56) : 0

    const titleBlock = title
      ? `<h1 style="margin:0;font-size:${titleFont}px;line-height:1.12;font-weight:900;color:#ffffff;flex-shrink:0;">${title}</h1>`
      : ""

    const imageBlock = hasImage
      ? `<div style="border-radius:18px;overflow:hidden;height:460px;background:#0f1c19;flex-shrink:0;">
           <img src="${this.imageValue}" crossorigin="anonymous" style="width:100%;height:100%;object-fit:cover;display:block;" />
         </div>`
      : ""

    wrap.innerHTML = `
      <div style="display:flex;align-items:center;gap:14px;font-weight:800;flex-shrink:0;">
        <div style="width:44px;height:44px;border-radius:12px;background:#34d399;display:flex;align-items:center;justify-content:center;color:#042f1d;font-weight:900;font-size:22px;">B</div>
        <div style="font-size:22px;color:#c8d3cf;">Faith Community</div>
      </div>

      <div style="display:flex;flex-direction:column;gap:18px;flex:1 1 auto;min-height:0;">
        <div style="font-size:16px;font-weight:800;letter-spacing:0.22em;text-transform:uppercase;color:#34d399;flex-shrink:0;">A Breath</div>
        ${titleBlock}
        ${imageBlock}
        <div style="font-size:${bodyFont}px;line-height:${bodyLine};color:#dde6e2;font-weight:400;white-space:pre-wrap;overflow:hidden;flex:1 1 auto;">${snippet}</div>
      </div>

      <div style="display:flex;align-items:center;justify-content:space-between;border-top:1px solid rgba(255,255,255,0.10);padding-top:24px;flex-shrink:0;">
        <div style="display:flex;align-items:center;gap:14px;">
          <div style="width:48px;height:48px;border-radius:50%;background:#34d399;color:#042f1d;display:flex;align-items:center;justify-content:center;font-weight:900;font-size:22px;">
            ${safe(author.charAt(0).toUpperCase())}
          </div>
          <div>
            <div style="font-weight:800;font-size:22px;color:#ffffff;">@${author}</div>
            <div style="color:#8a9893;font-size:16px;">read more on Faith Community</div>
          </div>
        </div>
        <div style="font-size:16px;color:#8a9893;font-weight:700;">Tap to read →</div>
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
