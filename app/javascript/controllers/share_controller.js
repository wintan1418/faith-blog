import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url:         String,
    title:       String,
    author:      String,
    snippet:     String,
    image:       String,
    accent:      { type: String, default: "#34d399" },
    accentDeep:  { type: String, default: "#10b981" }
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
    this.openProgress("Preparing snapshot…", "Drawing your breath")

    try {
      let postImage = null
      if (this.imageValue && this.imageValue.length > 1) {
        this.updateProgress("Loading attachment…", "Fetching the image")
        await this.nextFrame()
        try {
          postImage = await this.loadImage(this.imageValue)
        } catch (e) {
          console.warn("Snapshot: image failed to load, continuing without it", e)
        }
      }

      this.updateProgress("Rendering image…", "Almost there")
      await this.nextFrame()

      const canvas = this.drawSnapshotCanvas(postImage)

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
    }
  }

  loadImage(src) {
    return new Promise((resolve, reject) => {
      const img = new Image()
      img.crossOrigin = "anonymous"
      const timer = setTimeout(() => reject(new Error("image load timeout")), 6000)
      img.onload  = () => { clearTimeout(timer); resolve(img) }
      img.onerror = (e) => { clearTimeout(timer); reject(e) }
      img.src = src
    })
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

  drawSnapshotCanvas(postImage) {
    const W = 1080, H = 1350
    const PAD_X = 72, PAD_TOP = 72, PAD_BOTTOM = 88
    const innerW = W - PAD_X * 2
    const FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"

    const canvas = document.createElement("canvas")
    canvas.width = W
    canvas.height = H
    const ctx = canvas.getContext("2d")

    // Background — diagonal gradient matching the previous look.
    const bg = ctx.createLinearGradient(0, 0, W, H)
    bg.addColorStop(0,   "#0b0f10")
    bg.addColorStop(0.6, "#111a18")
    bg.addColorStop(1,   "#0e1f1a")
    ctx.fillStyle = bg
    ctx.fillRect(0, 0, W, H)

    const title   = (this.titleValue   || "").replace(/[<>]/g, "")
    const snippet = (this.snippetValue || "").replace(/[<>]/g, "")
    const author  = (this.authorValue  || "anonymous").replace(/[<>]/g, "")
    const hasImage = !!postImage

    let y = PAD_TOP

    // Brand badge + name — fill with the post author's accent
    const accent = this.accentValue || "#34d399"
    const badge = 44
    const badgeGrad = ctx.createLinearGradient(PAD_X, y, PAD_X + badge, y + badge)
    badgeGrad.addColorStop(0, accent)
    badgeGrad.addColorStop(1, this.accentDeepValue || accent)
    this.roundedRectPath(ctx, PAD_X, y, badge, badge, 12)
    ctx.fillStyle = badgeGrad
    ctx.fill()
    ctx.fillStyle = "#042f1d"
    ctx.font = `900 22px ${FONT}`
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillText("B", PAD_X + badge / 2, y + badge / 2 + 2)

    ctx.fillStyle = "#c8d3cf"
    ctx.font = `800 22px ${FONT}`
    ctx.textAlign = "left"
    ctx.textBaseline = "middle"
    ctx.fillText("Faith Community", PAD_X + badge + 14, y + badge / 2 + 1)

    y += badge + 28

    // Eyebrow — "A BREATH" with letter-spacing
    ctx.fillStyle = accent
    ctx.font = `800 16px ${FONT}`
    ctx.textAlign = "left"
    ctx.textBaseline = "top"
    this.drawTrackedText(ctx, "A BREATH", PAD_X, y, 16 * 0.22)
    y += 16 + 18

    // Title (optional)
    if (title) {
      const titleSize = title.length > 60 ? 44 : 56
      ctx.fillStyle = "#ffffff"
      ctx.font = `900 ${titleSize}px ${FONT}`
      const lines = this.wrapText(ctx, title, innerW)
      const lh = titleSize * 1.12
      lines.forEach((line, i) => ctx.fillText(line, PAD_X, y + i * lh))
      y += lines.length * lh + 18
    }

    // Image (optional) — cover-fit into rounded box.
    if (hasImage) {
      const imgH = 460
      ctx.save()
      this.roundedRectPath(ctx, PAD_X, y, innerW, imgH, 18)
      ctx.fillStyle = "#0f1c19"
      ctx.fill()
      ctx.clip()
      const ratio = postImage.naturalWidth / postImage.naturalHeight
      const target = innerW / imgH
      let dw, dh, dx, dy
      if (ratio > target) {
        dh = imgH; dw = imgH * ratio
        dx = PAD_X - (dw - innerW) / 2; dy = y
      } else {
        dw = innerW; dh = innerW / ratio
        dx = PAD_X; dy = y - (dh - imgH) / 2
      }
      ctx.drawImage(postImage, dx, dy, dw, dh)
      ctx.restore()
      y += imgH + 18
    }

    // Footer geometry — compute first so body knows where to stop.
    const avatarSize = 48
    const footerTop = H - PAD_BOTTOM - avatarSize           // top of avatar
    const dividerY  = footerTop - 24                        // 24px padding-top
    const bodyMaxBottom = dividerY - 14

    // Body text
    const len = snippet.length
    let bodySize, bodyLineMul
    if (hasImage) {
      bodySize    = len > 700 ? 22 : len > 400 ? 26 : len > 200 ? 28 : 30
      bodyLineMul = 1.4
    } else {
      bodySize    = len > 1100 ? 22 : len > 700 ? 26 : len > 400 ? 30 : 34
      bodyLineMul = bodySize >= 30 ? 1.45 : 1.4
    }

    ctx.fillStyle = "#dde6e2"
    ctx.font = `400 ${bodySize}px ${FONT}`
    ctx.textBaseline = "top"
    const bodyLines = this.wrapText(ctx, snippet, innerW)
    const lh = bodySize * bodyLineMul
    const maxLines = Math.max(1, Math.floor((bodyMaxBottom - y) / lh))
    const display  = bodyLines.slice(0, maxLines)
    if (bodyLines.length > maxLines && display.length) {
      let last = display[display.length - 1]
      while (ctx.measureText(last + "…").width > innerW && last.length > 1) {
        last = last.slice(0, -1)
      }
      display[display.length - 1] = last.replace(/\s+$/, "") + "…"
    }
    display.forEach((line, i) => ctx.fillText(line, PAD_X, y + i * lh))

    // Divider
    ctx.strokeStyle = "rgba(255,255,255,0.10)"
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(PAD_X, dividerY)
    ctx.lineTo(W - PAD_X, dividerY)
    ctx.stroke()

    // Avatar
    ctx.fillStyle = accent
    ctx.beginPath()
    ctx.arc(PAD_X + avatarSize / 2, footerTop + avatarSize / 2, avatarSize / 2, 0, Math.PI * 2)
    ctx.fill()
    ctx.fillStyle = "#042f1d"
    ctx.font = `900 22px ${FONT}`
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillText(author.charAt(0).toUpperCase(), PAD_X + avatarSize / 2, footerTop + avatarSize / 2 + 2)

    // Author handle + read-more line
    ctx.textAlign = "left"
    ctx.textBaseline = "top"
    ctx.fillStyle = "#ffffff"
    ctx.font = `800 22px ${FONT}`
    ctx.fillText("@" + author, PAD_X + avatarSize + 14, footerTop + 2)
    ctx.fillStyle = "#8a9893"
    ctx.font = `600 16px ${FONT}`
    ctx.fillText("read more on Faith Community", PAD_X + avatarSize + 14, footerTop + 28)

    // CTA
    ctx.textAlign = "right"
    ctx.fillStyle = "#8a9893"
    ctx.font = `700 16px ${FONT}`
    ctx.fillText("Tap to read →", W - PAD_X, footerTop + 16)

    return canvas
  }

  roundedRectPath(ctx, x, y, w, h, r) {
    ctx.beginPath()
    ctx.moveTo(x + r, y)
    ctx.lineTo(x + w - r, y)
    ctx.quadraticCurveTo(x + w, y, x + w, y + r)
    ctx.lineTo(x + w, y + h - r)
    ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
    ctx.lineTo(x + r, y + h)
    ctx.quadraticCurveTo(x, y + h, x, y + h - r)
    ctx.lineTo(x, y + r)
    ctx.quadraticCurveTo(x, y, x + r, y)
    ctx.closePath()
  }

  drawTrackedText(ctx, text, x, y, spacing) {
    let cx = x
    for (const ch of text) {
      ctx.fillText(ch, cx, y)
      cx += ctx.measureText(ch).width + spacing
    }
  }

  wrapText(ctx, text, maxWidth) {
    const out = []
    const paragraphs = String(text).split(/\n/)
    paragraphs.forEach((para, idx) => {
      if (!para.trim()) {
        if (idx !== paragraphs.length - 1) out.push("")
        return
      }
      const words = para.split(/\s+/).filter(Boolean)
      let line = ""
      for (const w of words) {
        const test = line ? `${line} ${w}` : w
        if (ctx.measureText(test).width > maxWidth && line) {
          out.push(line)
          line = w
        } else {
          line = test
        }
      }
      if (line) out.push(line)
    })
    return out
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
