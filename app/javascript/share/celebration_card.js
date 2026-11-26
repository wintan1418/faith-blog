// Brethreign Celebrates: the occasion card ("Happy Thanksgiving from
// Brethreign") for status and feeds, in Story (1080x1920) or Square
// (1080x1080), light or dark. Drawn on a canvas like the breath cards
// (share/card_renderer.js) and shared the same way: the app's share bridge,
// the phone's share sheet, or a download. Loaded on demand.

import {
  FORMATS, STACK, THEMES, drawLines, fitText, roundRect, drawLockup,
  drawQR, hexToRgba, loadImage, canvasToBlob
} from "./card_renderer"

const SERIF = `Fraunces, "Playfair Display", Georgia, "Times New Roman", serif`
const CARD_FORMATS = { story: FORMATS.story, square: FORMATS.square }
const STORE_KEY = "br-celebration-card"

const remember = (value) => { try { localStorage.setItem(STORE_KEY, JSON.stringify(value)) } catch { /* private mode */ } }
const recall = () => { try { return JSON.parse(localStorage.getItem(STORE_KEY) || "{}") || {} } catch { return {} } }

function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag)
  for (const [key, value] of Object.entries(attrs)) {
    if (value === undefined || value === null || value === false) continue
    if (key === "text") node.textContent = value
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value)
    else node.setAttribute(key, value === true ? "" : value)
  }
  for (const child of [].concat(children)) if (child) node.append(typeof child === "string" ? document.createTextNode(child) : child)
  return node
}

// ── Drawing ──

// A deterministic scatter (same card every time) of the occasion's motif.
function drawMotif(ctx, effect, x, y, w, h, color) {
  let seed = 7
  const rand = () => { seed = (seed * 9301 + 49297) % 233280; return seed / 233280 }
  ctx.save()
  roundRect(ctx, x, y, w, h, 0)
  ctx.clip()
  for (let i = 0; i < 26; i++) {
    const px = x + rand() * w, py = y + rand() * h, s = 6 + rand() * 12, a = 0.18 + rand() * 0.3
    ctx.globalAlpha = a
    ctx.fillStyle = i % 3 === 0 ? "#ffffff" : color
    ctx.save()
    ctx.translate(px, py)
    ctx.rotate(rand() * Math.PI)
    if (effect === "confetti") { ctx.fillRect(-s / 2, -s / 4, s, s / 2) }
    else if (effect === "leaves" || effect === "petals") {
      ctx.beginPath(); ctx.ellipse(0, 0, s, s / (effect === "leaves" ? 2.2 : 1.6), 0, 0, Math.PI * 2); ctx.fill()
    } else if (effect === "lights" || effect === "stars") {
      ctx.globalAlpha = a + 0.2
      ctx.shadowColor = color; ctx.shadowBlur = s * 1.6
      ctx.beginPath(); ctx.arc(0, 0, s / 3, 0, Math.PI * 2); ctx.fill()
    } else {
      ctx.beginPath(); ctx.arc(0, 0, s / 4, 0, Math.PI * 2); ctx.fill()
    }
    ctx.restore()
  }
  ctx.restore()
}

function coverImage(ctx, img, x, y, w, h, r) {
  ctx.save()
  roundRect(ctx, x, y, w, h, r)
  ctx.clip()
  const ratio = img.naturalWidth / img.naturalHeight
  let dw = w, dh = w / ratio
  if (dh < h) { dh = h; dw = h * ratio }
  ctx.drawImage(img, x + (w - dw) / 2, y + (h - dh) / 2, dw, dh)
  ctx.restore()
}

// The art band at the top of the card: the uploaded artwork, or the built-in
// theme (an accent wash, the motif and the emblem in a soft ring).
function drawArt(ctx, data, art, x, y, w, h, r) {
  if (art) return coverImage(ctx, art, x, y, w, h, r)
  ctx.save()
  roundRect(ctx, x, y, w, h, r)
  ctx.clip()
  const g = ctx.createLinearGradient(x, y, x + w, y + h)
  g.addColorStop(0, data.accent)
  g.addColorStop(1, shade(data.accent, -0.35))
  ctx.fillStyle = g
  ctx.fillRect(x, y, w, h)
  const glow = ctx.createRadialGradient(x + w * 0.5, y + h * 0.55, 0, x + w * 0.5, y + h * 0.55, w * 0.6)
  glow.addColorStop(0, "rgba(255,255,255,0.22)")
  glow.addColorStop(1, "rgba(255,255,255,0)")
  ctx.fillStyle = glow
  ctx.fillRect(x, y, w, h)
  ctx.restore()
  drawMotif(ctx, data.effect, x, y, w, h, "#ffe9b8")
  const cx = x + w / 2, cy = y + h / 2, ring = Math.min(h * 0.36, 150)
  ctx.save()
  ctx.strokeStyle = "rgba(255,255,255,0.35)"
  ctx.lineWidth = 3
  ctx.beginPath(); ctx.arc(cx, cy, ring, 0, Math.PI * 2); ctx.stroke()
  ctx.fillStyle = "rgba(255,255,255,0.12)"
  ctx.beginPath(); ctx.arc(cx, cy, ring - 14, 0, Math.PI * 2); ctx.fill()
  ctx.font = `${Math.round(ring * 0.95)}px ${STACK}`
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"
  ctx.fillStyle = "#ffffff"
  ctx.fillText(data.emblem || "✨", cx, cy + ring * 0.06)
  ctx.restore()
}

function shade(hex, amount) {
  const h = String(hex || "#0e5c43").replace("#", "")
  const n = parseInt(h, 16)
  const mix = (c) => Math.max(0, Math.min(255, Math.round(amount < 0 ? c * (1 + amount) : c + (255 - c) * amount)))
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(mix)
  return `#${((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1)}`
}

function centered(ctx, text, cx, y, font, color) {
  ctx.font = font
  ctx.fillStyle = color
  ctx.textAlign = "center"
  ctx.textBaseline = "alphabetic"
  ctx.fillText(text, cx, y)
}

function serifLines(ctx, text, { size, weight, italic, maxWidth }) {
  ctx.font = `${italic ? "italic " : ""}${weight} ${size}px ${SERIF}`
  const words = String(text || "").split(/\s+/).filter(Boolean)
  const lines = []
  let line = ""
  for (const word of words) {
    const next = line ? `${line} ${word}` : word
    if (line && ctx.measureText(next).width > maxWidth) { lines.push(line); line = word } else line = next
  }
  if (line) lines.push(line)
  return lines
}

// The card itself. data: { title, message, verse, reference, accent, emblem,
// effect, username, qr }; opts: { format, theme, art }.
export function renderCelebrationCard(data, { format = "story", theme = "light", art = null } = {}) {
  const f = CARD_FORMATS[format] || CARD_FORMATS.story
  const t = THEMES[theme] || THEMES.light
  const story = format === "story"
  const canvas = document.createElement("canvas")
  canvas.width = f.width
  canvas.height = f.height
  const ctx = canvas.getContext("2d")
  const W = f.width, H = f.height
  const accent = data.accent || "#0e5c43"
  const accentInk = theme === "dark" ? shade(accent, 0.45) : accent

  // Frame: the house paper, warmed by the occasion's colour.
  const frame = ctx.createLinearGradient(0, 0, 0, H)
  frame.addColorStop(0, t.frame[0])
  frame.addColorStop(1, t.frame[1])
  ctx.fillStyle = frame
  ctx.fillRect(0, 0, W, H)
  const wash = ctx.createRadialGradient(W * 0.5, 0, 0, W * 0.5, 0, H * 0.8)
  wash.addColorStop(0, hexToRgba(accent, t.glow))
  wash.addColorStop(1, hexToRgba(accent, 0))
  ctx.fillStyle = wash
  ctx.fillRect(0, 0, W, H)

  const m = story ? 64 : 44
  const pad = story ? 72 : 52
  const r = story ? 48 : 40
  const cardX = m, cardY = m, cardW = W - m * 2, cardH = H - m * 2
  ctx.save()
  ctx.shadowColor = t.shadow
  ctx.shadowBlur = 60
  ctx.shadowOffsetY = 18
  ctx.fillStyle = t.card
  roundRect(ctx, cardX, cardY, cardW, cardH, r)
  ctx.fill()
  ctx.restore()

  const innerW = cardW - pad * 2
  const cx = W / 2
  // Art band
  const artH = story ? 620 : 300
  drawArt(ctx, { ...data, accent }, art, cardX + 18, cardY + 18, cardW - 36, artH, r - 14)

  // Foot: logo + address on the left, QR on the right.
  const qrSize = story ? 200 : 132
  const footY = cardY + cardH - pad - qrSize
  const lockH = story ? 60 : 42
  drawLockup(ctx, cardX + pad, footY + (qrSize - lockH) / 2 - (story ? 18 : 12), lockH, accentInk, t.ink)
  ctx.font = `500 ${story ? 30 : 22}px ${STACK}`
  ctx.fillStyle = t.muted
  ctx.textAlign = "left"
  ctx.textBaseline = "alphabetic"
  ctx.fillText("brethreign.com", cardX + pad + (story ? 4 : 2), footY + (qrSize + lockH) / 2 + (story ? 28 : 18))
  if (data.qr?.length) drawQR(ctx, data.qr, cardX + cardW - pad - qrSize, footY, qrSize, "#14201b")
  ctx.strokeStyle = t.line
  ctx.lineWidth = 2
  ctx.beginPath(); ctx.moveTo(cardX + pad, footY - (story ? 44 : 28)); ctx.lineTo(cardX + cardW - pad, footY - (story ? 44 : 28)); ctx.stroke()

  // Body, centred between the art and the foot.
  const top = cardY + 18 + artH + (story ? 70 : 40)
  const bottom = footY - (story ? 80 : 50)
  const blocks = []
  const kickerSize = story ? 28 : 21
  blocks.push({ h: kickerSize * 1.6, draw: (y) => {
    ctx.save()
    ctx.font = `700 ${kickerSize}px ${STACK}`
    if ("letterSpacing" in ctx) ctx.letterSpacing = `${Math.round(kickerSize * 0.18)}px`
    centered(ctx, "BRETHREIGN CELEBRATES", cx, y + kickerSize, ctx.font, accentInk)
    ctx.restore()
  } })

  const titleSizes = story ? [96, 88, 80, 72, 64] : [66, 60, 54, 48]
  let titleLines, titleSize
  for (const size of titleSizes) {
    titleSize = size
    titleLines = serifLines(ctx, data.title, { size, weight: 700, maxWidth: innerW })
    if (titleLines.length <= 2) break
  }
  const titleLh = titleSize * 1.12
  blocks.push({ h: titleLines.length * titleLh + (story ? 12 : 6), draw: (y) => {
    titleLines.forEach((line, i) => centered(ctx, line, cx, y + titleLh * (i + 0.82), `700 ${titleSize}px ${SERIF}`, t.ink))
  } })
  const fromSize = story ? 34 : 25
  blocks.push({ h: fromSize * 1.9, draw: (y) => centered(ctx, "from Brethreign", cx, y + fromSize * 1.2, `italic 400 ${fromSize}px ${SERIF}`, t.muted) })

  const fixedH = blocks.reduce((s, b) => s + b.h, 0)
  const signSize = story ? 34 : 25
  const signH = data.username ? signSize * 2.2 : 0
  const verseRoom = Math.max(0, bottom - top - fixedH - signH - (story ? 40 : 20))

  if (data.verse && verseRoom > 60) {
    const sizes = story ? [50, 46, 42, 38, 35, 32] : [32, 30, 28, 26, 24]
    const fit = fitText(ctx, `“${data.verse}”`, { sizes, weight: 400, maxWidth: innerW - (story ? 40 : 20), maxHeight: verseRoom - sizes[0] * 1.6, lineHeight: 1.45, base: { italic: true } })
    const refSize = Math.round(fit.size * 0.72)
    blocks.push({ h: fit.height + refSize * 2.4 + (story ? 30 : 14), draw: (y) => {
      ctx.save()
      ctx.fillStyle = hexToRgba(accent, 0.6)
      roundRect(ctx, cx - 40, y, 80, 5, 3)
      ctx.fill()
      ctx.restore()
      const vy = y + (story ? 30 : 16)
      fit.lines.forEach((line, i) => {
        const lineOnly = { ...line, gapBefore: false }
        const w = line.width
        drawLines(ctx, [lineOnly], cx - w / 2, vy + i * fit.lh, { size: fit.size, lh: fit.lh, color: t.soft })
      })
      centered(ctx, `${data.reference || ""}  ·  KJV`, cx, vy + fit.height + refSize * 1.5, `700 ${refSize}px ${STACK}`, accentInk)
    } })
  } else if (data.message) {
    const sizes = story ? [42, 38, 34] : [28, 26, 24]
    const fit = fitText(ctx, data.message, { sizes, maxWidth: innerW, maxHeight: Math.max(verseRoom, 80), lineHeight: 1.45 })
    blocks.push({ h: fit.height + 10, draw: (y) => {
      fit.lines.forEach((line, i) => drawLines(ctx, [{ ...line, gapBefore: false }], cx - line.width / 2, y + i * fit.lh, { size: fit.size, lh: fit.lh, color: t.soft }))
    } })
  }

  if (data.username) {
    blocks.push({ h: signH, draw: (y) => centered(ctx, `— from @${data.username}`, cx, y + signSize * 1.6, `600 ${signSize}px ${STACK}`, t.ink) })
  }

  const total = blocks.reduce((s, b) => s + b.h, 0)
  let y = top + Math.max(0, (bottom - top - total) / 2)
  for (const block of blocks) { block.draw(y); y += block.h }
  return canvas
}

// ── The sheet ──

async function loadFonts() {
  const fonts = document.fonts
  if (!fonts?.load) return
  await Promise.all(["400 32px Inter", "600 32px Inter", "700 32px Inter", "italic 400 32px Inter",
    "700 64px Fraunces", "italic 400 32px Fraunces"].map(f => fonts.load(f).catch(() => null)))
}

async function loadArt(art) {
  if (!art) return null
  for (const src of [art.url, art.fallback]) {
    if (!src) continue
    try { return await loadImage(src) } catch { /* next */ }
  }
  return null
}

async function loadQR(link) {
  if (!link) return null
  try {
    const url = new URL("/share/qr", window.location.origin)
    url.searchParams.set("url", link)
    const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
    return response.ok ? (await response.json()).qr || null : null
  } catch { return null }
}

class CelebrationSheet {
  constructor(data) {
    const saved = recall()
    this.data = data
    this.format = CARD_FORMATS[saved.format] ? saved.format : "story"
    this.theme = saved.theme === "dark" || saved.theme === "light" ? saved.theme : (document.documentElement.dataset.theme === "dark" ? "dark" : "light")
    this.native = window.BrethreignNative
    this.inApp = /Hotwire Native|Turbo Native/.test(navigator.userAgent)
  }

  open() {
    this.build()
    document.body.append(this.dialog)
    if (this.dialog.showModal) this.dialog.showModal()
    else this.dialog.setAttribute("open", "")
    this.load()
  }

  close() { this.dialog?.close?.(); this.dialog?.remove() }

  build() {
    this.status = el("p", { class: "share-sheet-status", role: "status", "aria-live": "polite" })
    this.stage = el("div", { class: "share-sheet-stage", "data-testid": "celebration-card-stage" }, [
      el("div", { class: "share-sheet-loading" }, [el("span", { class: "share-sheet-spinner", "aria-hidden": "true" }), el("span", { text: "Drawing your card…" })])
    ])
    this.formatButtons = Object.entries(CARD_FORMATS).map(([key, f]) =>
      el("button", { type: "button", class: "share-seg-btn", role: "radio", "data-format": key, "aria-checked": String(key === this.format), onclick: () => this.set({ format: key }) }, [
        el("span", { class: "share-seg-shape", "data-shape": key, "aria-hidden": "true" }),
        el("span", { class: "share-seg-text" }, [el("strong", { text: f.label }), el("small", { text: f.hint })])
      ]))
    this.themeButtons = ["light", "dark"].map(key =>
      el("button", { type: "button", class: "share-chip", role: "radio", "data-theme-choice": key, "aria-checked": String(key === this.theme), onclick: () => this.set({ theme: key }) },
        [el("span", { class: `share-chip-dot is-${key}`, "aria-hidden": "true" }), key === "light" ? "Light" : "Dark"]))
    this.shareButton = el("button", { type: "button", class: "share-btn share-btn-primary", "data-testid": "celebration-card-share", disabled: true, onclick: () => this.share() }, "Share")
    this.downloadButton = el("button", { type: "button", class: "share-btn", "data-testid": "celebration-card-download", disabled: true, onclick: () => this.download() }, "Download")

    const panel = el("div", { class: "share-sheet-panel" }, [
      el("header", { class: "share-sheet-head" }, [
        el("div", {}, [
          el("h2", { class: "share-sheet-title", text: "Share a celebration card" }),
          el("p", { class: "share-sheet-sub", text: "For your status, stories and feeds, signed with your name. The QR code brings people to Brethreign." })
        ]),
        el("button", { type: "button", class: "share-sheet-close", "aria-label": "Close", onclick: () => this.close() }, "×")
      ]),
      this.stage,
      el("div", { class: "share-sheet-controls" }, [
        el("div", { class: "share-seg", role: "radiogroup", "aria-label": "Image size" }, this.formatButtons),
        el("div", { class: "share-row" }, [
          el("span", { class: "share-row-label", text: "Card" }),
          el("div", { class: "share-chips", role: "radiogroup", "aria-label": "Card theme" }, this.themeButtons)
        ])
      ]),
      el("footer", { class: "share-sheet-foot" }, [this.status, el("div", { class: "share-sheet-actions" }, [this.downloadButton, this.shareButton])])
    ])
    this.dialog = el("dialog", { class: "share-sheet cel-card-sheet", "aria-label": "Share a celebration card" }, panel)
    this.dialog.addEventListener("click", (e) => { if (e.target === this.dialog) this.close() })
    this.dialog.addEventListener("close", () => this.dialog.remove())
  }

  async load() {
    const [art, qr] = await Promise.all([loadArt(this.data.art), loadQR(this.data.link), loadFonts()])
    this.art = art
    this.data = { ...this.data, qr }
    this.render()
  }

  set(change) {
    Object.assign(this, change)
    this.formatButtons.forEach(b => b.setAttribute("aria-checked", String(b.dataset.format === this.format)))
    this.themeButtons.forEach(b => b.setAttribute("aria-checked", String(b.dataset.themeChoice === this.theme)))
    remember({ format: this.format, theme: this.theme })
    this.render()
  }

  render() {
    try {
      this.canvas = renderCelebrationCard(this.data, { format: this.format, theme: this.theme, art: this.art })
    } catch {
      this.stage.replaceChildren(el("p", { class: "share-sheet-error", text: "Couldn't draw the card on this device." }))
      return
    }
    this.canvas.className = "share-sheet-canvas"
    this.canvas.setAttribute("role", "img")
    this.canvas.setAttribute("aria-label", `${this.data.title} card`)
    this.canvas.dataset.testid = "celebration-card-canvas"
    this.stage.dataset.previewFormat = this.format
    this.stage.dataset.previewTheme = this.theme
    this.stage.replaceChildren(el("figure", { class: "share-slide" }, this.canvas))
    const nativeOk = !!this.native?.shareImage
    this.shareButton.hidden = !(nativeOk || this.canShareFiles())
    this.shareButton.disabled = false
    this.downloadButton.hidden = this.inApp
    this.downloadButton.disabled = false
    if (this.inApp && !nativeOk) this.status.textContent = "Update the Brethreign app to share images."
  }

  canShareFiles(files) {
    if (!navigator.share || !navigator.canShare) return false
    try {
      return navigator.canShare({ files: files || [new File([new Blob(["x"], { type: "image/png" })], "probe.png", { type: "image/png" })] })
    } catch { return false }
  }

  fileName() { return `brethreign-celebrates-${this.data.id}-${this.format}.png` }

  async share() {
    if (!this.canvas) return
    const text = this.data.share_text
    try {
      if (this.native?.shareImage) return this.native.shareImage(this.canvas.toDataURL("image/png"), text)
      const file = new File([await canvasToBlob(this.canvas)], this.fileName(), { type: "image/png" })
      if (this.canShareFiles([file])) {
        await navigator.share({ files: [file], text, title: this.data.title })
        this.status.textContent = "Shared"
        return
      }
      this.save(file)
    } catch (error) {
      if (error?.name !== "AbortError") this.status.textContent = "Couldn't open the share sheet. Try Download instead."
    }
  }

  async download() {
    if (!this.canvas) return
    this.save(new File([await canvasToBlob(this.canvas)], this.fileName(), { type: "image/png" }))
  }

  save(file) {
    const url = URL.createObjectURL(file)
    const a = el("a", { href: url, download: file.name })
    document.body.append(a)
    a.click()
    a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 4000)
    this.status.textContent = "Saved to your downloads"
  }
}

export function openCelebrationCard(data) {
  const sheet = new CelebrationSheet(data)
  sheet.open()
  return sheet
}
