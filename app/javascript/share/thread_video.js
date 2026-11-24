// "Share as thread" as one short vertical video (1080x1920, 30fps) for
// WhatsApp / Instagram status, LinkedIn and X: a short intro, the cards of the
// thread scrolling past one by one (joined by a thread line, like X), and an
// end card with the QR code and short link.
//
// Each card is drawn once by card_renderer (bare, so it looks exactly like the
// image cards) and every frame only composites those bitmaps.
//
// Encoding happens in the browser: WebCodecs H.264 + mp4-muxer (moov at the
// front) when available, faster than real time; otherwise MediaRecorder on
// the canvas in real time (MP4 where the browser can, else WebM).
import { Muxer, ArrayBufferTarget } from "mp4-muxer"
import { renderCard, THEMES, STACK, LOGO_W, LOGO_H, drawLogo, drawQR, hexToRgba, fitText, drawLines, roundRect, plainText } from "./card_renderer"

export const W = 1080
export const H = 1920
export const FPS = 30
const BITRATE = 5_000_000

const INTRO = 1.8      // seconds before the first card has landed
const OUTRO = 3.0      // end card
const MOVE = 0.75      // card-to-card scroll
const GAP = 120        // between cards on the strip (shadow room included)
const VIEW_TOP = 250   // the cards live between the header…
const VIEW_BOTTOM = H - 230 // …and the dots

// H.264 profiles WhatsApp and Instagram take: Main, Constrained Baseline, then
// High; level 4.0 covers 1080x1920 at 30fps, 4.1/4.2 for picky encoders.
const CODECS = ["avc1.4d0028", "avc1.42e028", "avc1.640028", "avc1.4d0029", "avc1.42e029", "avc1.640029", "avc1.4d002a", "avc1.64002a"]

const RECORDER_TYPES = [
  ["video/mp4;codecs=avc1.42E01E", "mp4"], ["video/mp4;codecs=avc1", "mp4"], ["video/mp4", "mp4"],
  ["video/webm;codecs=vp9", "webm"], ["video/webm;codecs=vp8", "webm"], ["video/webm", "webm"]
]

const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v))
const lerp = (a, b, t) => a + (b - a) * t
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2)
const easeOut = (t) => 1 - Math.pow(1 - t, 3)
const easeIn = (t) => t * t * t

// Hands the main thread back between frames (faster than setTimeout's 4ms clamp).
const channel = typeof MessageChannel !== "undefined" ? new MessageChannel() : null
const queue = []
if (channel) channel.port1.onmessage = () => queue.shift()?.()
const yieldToPage = () => new Promise(resolve => {
  if (channel) { queue.push(resolve); channel.port2.postMessage(0) } else setTimeout(resolve, 0)
})

let codecCheck
async function supportedCodec() {
  if (typeof VideoEncoder === "undefined" || typeof VideoFrame === "undefined") return null
  codecCheck ||= (async () => {
    for (const codec of CODECS) {
      try {
        const { supported } = await VideoEncoder.isConfigSupported(encoderConfig(codec))
        if (supported) return codec
      } catch { /* try the next one */ }
    }
    return null
  })()
  return codecCheck
}

function encoderConfig(codec) {
  return { codec, width: W, height: H, bitrate: BITRATE, framerate: FPS, avc: { format: "avc" }, latencyMode: "quality" }
}

function recorderType() {
  if (typeof MediaRecorder === "undefined" || !HTMLCanvasElement.prototype.captureStream) return null
  for (const [type, ext] of RECORDER_TYPES) {
    try { if (MediaRecorder.isTypeSupported(type)) return { type, ext } } catch { /* next */ }
  }
  return null
}

// What this browser can make: { method: "webcodecs" | "recorder", ext: "mp4" | "webm" } or null.
export async function videoSupport() {
  if (await supportedCodec()) return { method: "webcodecs", ext: "mp4" }
  const rec = recorderType()
  return rec ? { method: "recorder", ext: rec.ext } : null
}

export function timeline(count) {
  const per = clamp(15 / Math.max(1, count), 2.8, 3.6)
  return { per, duration: INTRO + count * per + OUTRO }
}

// ── The scene ──

class Scene {
  constructor(data, { theme, assets, replies }) {
    this.data = data
    this.theme = theme === "dark" ? "dark" : "light"
    this.T = THEMES[this.theme]
    this.accent = data.accent || "#34d399"
    this.accentDeep = data.accent_deep || this.accent
    this.accentText = this.theme === "dark" ? this.accent : this.accentDeep

    const total = replies.length + 1
    const base = { format: "story", theme: this.theme, assets, total, bare: true }
    this.cards = [renderCard(data, { ...base, index: 1 })]
    replies.forEach((reply, i) => this.cards.push(renderCard(data, { ...base, reply, index: i + 2 })))

    // The strip: each card box follows the previous one by GAP. boxes[i] is
    // where card i's box starts, tops[i] where its canvas (with shadow) starts.
    let boxY = 0
    this.boxes = this.cards.map(c => { const b = boxY; boxY += c.cardBox.h + GAP; return b })
    this.tops = this.cards.map((c, i) => this.boxes[i] - c.cardBox.y)
    const viewH = VIEW_BOTTOM - VIEW_TOP
    this.cams = this.cards.map((c, i) => this.boxes[i] - VIEW_TOP - Math.max(0, (viewH - c.cardBox.h) / 2))

    const { per, duration } = timeline(this.cards.length)
    this.per = per
    this.duration = duration
    this.outroAt = INTRO + this.cards.length * per

    this.canvas = document.createElement("canvas")
    this.canvas.width = W
    this.canvas.height = H
    this.ctx = this.canvas.getContext("2d", { alpha: false })

    this.background = this.makeBackground()
    this.glowSprite = this.makeGlow()
    this.header = this.makeHeader()
    this.footer = this.makeBand(VIEW_BOTTOM - 40, H, false)
    this.intro = this.makeIntro()
    this.outro = this.makeOutro()
  }

  layer(h = H) {
    const c = document.createElement("canvas")
    c.width = W
    c.height = h
    return c
  }

  makeBackground() {
    const c = this.layer()
    const ctx = c.getContext("2d")
    const g = ctx.createLinearGradient(0, 0, W, H)
    g.addColorStop(0, this.T.frame[0])
    g.addColorStop(1, this.T.frame[1])
    ctx.fillStyle = g
    ctx.fillRect(0, 0, W, H)
    const glow = (x, y, r, color, a) => {
      const rg = ctx.createRadialGradient(x, y, 0, x, y, r)
      rg.addColorStop(0, hexToRgba(color, a))
      rg.addColorStop(1, hexToRgba(color, 0))
      ctx.fillStyle = rg
      ctx.fillRect(0, 0, W, H)
    }
    glow(W, 0, W * 0.95, this.accent, this.T.glow)
    glow(0, H, W * 0.85, this.accentDeep, this.T.glow * 0.55)
    return c
  }

  // A soft accent light that drifts slowly behind everything.
  makeGlow() {
    const s = 512
    const c = document.createElement("canvas")
    c.width = c.height = s
    const ctx = c.getContext("2d")
    const rg = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2)
    rg.addColorStop(0, hexToRgba(this.accent, this.T.glow * 0.7))
    rg.addColorStop(1, hexToRgba(this.accent, 0))
    ctx.fillStyle = rg
    ctx.fillRect(0, 0, s, s)
    return c
  }

  // A slice of the background that fades out towards the cards, so cards
  // slide softly under the header and the dots.
  makeBand(from, to, fadeDown) {
    const c = this.layer(to - from)
    const ctx = c.getContext("2d")
    ctx.drawImage(this.background, 0, from, W, to - from, 0, 0, W, to - from)
    ctx.globalCompositeOperation = "destination-in"
    const g = ctx.createLinearGradient(0, 0, 0, to - from)
    if (fadeDown) { g.addColorStop(0, "#000"); g.addColorStop(0.6, "#000"); g.addColorStop(1, "rgba(0,0,0,0)") } else { g.addColorStop(0, "rgba(0,0,0,0)"); g.addColorStop(0.3, "#000"); g.addColorStop(1, "#000") }
    ctx.fillStyle = g
    ctx.fillRect(0, 0, W, to - from)
    ctx.globalCompositeOperation = "source-over"
    c.top = from
    return c
  }

  brand(ctx, cx, y, logoH, size) {
    ctx.font = `700 ${size}px ${STACK}`
    const wordW = ctx.measureText("Brethreign").width
    const lw = LOGO_W * (logoH / LOGO_H)
    const x = cx - (lw + 16 + wordW) / 2
    drawLogo(ctx, x, y, logoH, this.accentText)
    ctx.fillStyle = this.T.ink
    ctx.textAlign = "left"
    ctx.textBaseline = "middle"
    ctx.fillText("Brethreign", x + lw + 16, y + logoH / 2 + 2)
  }

  makeHeader() {
    const c = this.makeBand(0, VIEW_TOP + 110, true)
    const ctx = c.getContext("2d")
    this.brand(ctx, W / 2, 92, 62, 40)
    const voices = this.cards.length
    ctx.font = `600 28px ${STACK}`
    ctx.fillStyle = this.T.muted
    ctx.textAlign = "center"
    ctx.textBaseline = "alphabetic"
    ctx.fillText(voices > 1 ? `A thread · ${voices} voices` : "A breath", W / 2, 206)
    return c
  }

  authorLine() {
    const a = this.data.author || {}
    return a.anonymous ? "Shared anonymously" : `by ${a.name || ""}${a.username ? ` · @${a.username}` : ""}`
  }

  makeIntro() {
    const c = this.layer()
    const ctx = c.getContext("2d")
    const cx = W / 2
    const mark = 230
    const title = plainText(this.data.title || "") || plainText(this.data.text || "").slice(0, 140)
    const maxW = W - 180
    const fit = fitText(ctx, title, { sizes: [84, 76, 68, 60, 54], weight: 700, maxWidth: maxW, maxHeight: 460, lineHeight: 1.16, base: { bold: true } })
    // Mark, kicker, title and byline, centred as one block a little above the middle.
    const blockH = mark + 120 + 70 + fit.height + 100
    const top = Math.round(H * 0.47 - blockH / 2)

    drawLogo(ctx, cx - (LOGO_W * mark / LOGO_H) / 2, top, mark, this.accentText)
    ctx.textAlign = "center"
    ctx.textBaseline = "alphabetic"
    ctx.fillStyle = this.accentText
    ctx.font = `700 30px ${STACK}`
    const kicker = (this.cards.length > 1 ? "A THREAD ON BRETHREIGN" : "ON BRETHREIGN").split("").join(String.fromCharCode(8202))
    ctx.fillText(kicker, cx, top + mark + 120)
    let y = top + mark + 120 + 70
    // drawLines is left-aligned: centre each line by hand.
    fit.lines.forEach((line, i) => {
      if (line.gapBefore && i > 0) y += fit.lh * 0.45
      drawLines(ctx, [line], cx - line.width / 2, y, { size: fit.size, weight: 700, lh: fit.lh, color: this.T.ink })
      y += fit.lh
    })
    ctx.font = `500 34px ${STACK}`
    ctx.fillStyle = this.T.muted
    ctx.textAlign = "center"
    let who = this.authorLine()
    while (ctx.measureText(who).width > maxW && who.length > 6) who = who.slice(0, -2) + "…"
    ctx.fillText(who, cx, y + 70)
    return c
  }

  makeOutro() {
    const c = this.layer()
    const ctx = c.getContext("2d")
    const cx = W / 2
    this.brand(ctx, cx, 400, 84, 54)

    // The QR on a card of its own.
    const qs = 420
    const cardW = 560, cardH = 560
    const x = cx - cardW / 2, y = 630
    ctx.save()
    ctx.shadowColor = this.T.shadow
    ctx.shadowBlur = 60
    ctx.shadowOffsetY = 18
    ctx.fillStyle = "#ffffff"
    roundRect(ctx, x, y, cardW, cardH, 48)
    ctx.fill()
    ctx.restore()
    if (this.data.qr) drawQR(ctx, this.data.qr, cx - qs / 2, y + (cardH - qs) / 2, qs, "#0f1a16")
    else drawLogo(ctx, cx - (LOGO_W * 300 / LOGO_H) / 2, y + 130, 300, this.accentDeep)

    ctx.textAlign = "center"
    ctx.textBaseline = "alphabetic"
    ctx.fillStyle = this.T.ink
    ctx.font = `700 68px ${STACK}`
    ctx.fillText("Join the conversation", cx, y + cardH + 150)
    ctx.fillStyle = this.accentText
    ctx.font = `700 44px ${STACK}`
    let link = this.data.link_label || ""
    while (ctx.measureText(link).width > W - 140 && link.length > 6) link = link.slice(0, -2) + "…"
    ctx.fillText(link, cx, y + cardH + 225)
    ctx.fillStyle = this.T.muted
    ctx.font = `400 34px ${STACK}`
    ctx.fillText(this.data.qr ? "Scan or tap the link to read the whole thread" : "Read the whole thread and add your voice", cx, y + cardH + 290)
    return c
  }

  // Where the camera is (strip y at the top of the frame) and which card is in focus.
  camera(t) {
    const n = this.cards.length
    const first = this.cams[0]
    if (t < INTRO) {
      // The strip rises in from below during the end of the intro.
      const p = easeOut(clamp((t - (INTRO - 0.85)) / 0.85))
      return { cam: lerp(first - H * 0.9, first, p), focus: 0 }
    }
    if (t >= this.outroAt) {
      const p = easeIn(clamp((t - this.outroAt) / 0.8))
      return { cam: lerp(this.cams[n - 1], this.cams[n - 1] + H * 1.1, p), focus: n - 1 }
    }
    const k = (t - INTRO) / this.per
    const i = Math.min(n - 1, Math.floor(k))
    const into = (t - INTRO) - i * this.per
    const moveAt = this.per - MOVE
    if (i < n - 1 && into > moveAt) {
      const p = easeInOut(clamp((into - moveAt) / MOVE))
      return { cam: lerp(this.cams[i], this.cams[i + 1], p), focus: i + p }
    }
    return { cam: this.cams[i], focus: i }
  }

  draw(t) {
    const ctx = this.ctx
    const n = this.cards.length
    ctx.globalAlpha = 1
    ctx.drawImage(this.background, 0, 0)

    // Drifting light.
    const gs = 1500
    ctx.drawImage(this.glowSprite, W * 0.55 + Math.sin(t * 0.45) * 220 - gs / 2, H * 0.42 + Math.cos(t * 0.33) * 300 - gs / 2, gs, gs)

    const { cam, focus } = this.camera(t)
    const introOut = clamp((t - (INTRO - 0.8)) / 0.6) // 0 → 1 as the intro leaves
    const outroIn = clamp((t - this.outroAt - 0.35) / 0.7)

    // The thread line between cards, drawn in as the camera moves down.
    ctx.lineCap = "round"
    for (let i = 0; i < n - 1; i++) {
      const a = this.cards[i], b = this.cards[i + 1]
      const x = a.avatar.x
      const y1 = this.boxes[i] + a.cardBox.h - cam + 18
      const y2 = this.boxes[i + 1] - cam - 18
      if (y2 < -20 || y1 > H + 20) continue
      const grow = clamp(focus - i + 0.35, 0, 1)
      const yEnd = lerp(y1, y2, easeOut(grow))
      const g = ctx.createLinearGradient(0, y1, 0, y2)
      g.addColorStop(0, hexToRgba(this.accent, 0.95))
      g.addColorStop(1, hexToRgba(this.accentDeep, 0.95))
      ctx.strokeStyle = g
      ctx.lineWidth = 8
      ctx.beginPath()
      ctx.moveTo(x, y1)
      ctx.lineTo(x, yEnd)
      ctx.stroke()
      ctx.fillStyle = this.accent
      ctx.beginPath(); ctx.arc(x, y1, 10, 0, Math.PI * 2); ctx.fill()
      if (grow > 0.98) { ctx.beginPath(); ctx.arc(x, y2, 10, 0, Math.PI * 2); ctx.fill() }
    }

    // Cards: the one in focus full size and bright, the others set back a little.
    for (let i = 0; i < n; i++) {
      const c = this.cards[i]
      const top = this.tops[i] - cam
      if (top > H || top + c.height < 0) continue
      const d = Math.min(1, Math.abs(i - focus))
      const scale = 1 - 0.045 * d
      const alpha = 1 - 0.5 * d
      const cy = this.boxes[i] + c.cardBox.h / 2 - cam
      const w = c.width * scale, h = c.height * scale
      ctx.globalAlpha = alpha
      ctx.drawImage(c, (W - w) / 2, cy - (c.cardBox.y + c.cardBox.h / 2) * scale, w, h)
    }
    ctx.globalAlpha = 1

    // Header and dots fade in after the intro and out for the end card.
    const chrome = introOut * (1 - clamp((t - this.outroAt) / 0.5))
    if (chrome > 0) {
      ctx.globalAlpha = chrome
      ctx.drawImage(this.header, 0, 0)
      ctx.drawImage(this.footer, 0, this.footer.top)
      this.drawDots(ctx, focus)
      ctx.globalAlpha = 1
    }

    // Intro: in, hold, then up and away.
    if (introOut < 1) {
      const enter = easeOut(clamp(t / 0.7))
      ctx.globalAlpha = enter * (1 - introOut)
      ctx.drawImage(this.intro, 0, (1 - enter) * 60 - easeIn(introOut) * 260)
      ctx.globalAlpha = 1
    }

    if (outroIn > 0) {
      const p = easeOut(outroIn)
      ctx.globalAlpha = p
      ctx.drawImage(this.outro, 0, (1 - p) * 120)
      ctx.globalAlpha = 1
    }
  }

  drawDots(ctx, focus) {
    const n = this.cards.length
    if (n < 2) return
    const dot = 16, active = 52, space = 14
    const widths = this.cards.map((_, i) => lerp(active, dot, Math.min(1, Math.abs(i - focus))))
    const total = widths.reduce((a, b) => a + b, 0) + space * (n - 1)
    let x = (W - total) / 2
    const y = H - 150
    widths.forEach((w, i) => {
      const near = 1 - Math.min(1, Math.abs(i - focus))
      ctx.fillStyle = near > 0.5 ? this.accent : this.T.line.replace(/0\.10\)$/, "0.22)")
      roundRect(ctx, x, y, w, dot, dot / 2)
      ctx.fill()
      x += w + space
    })
    ctx.font = `600 30px ${STACK}`
    ctx.fillStyle = this.T.muted
    ctx.textAlign = "center"
    ctx.textBaseline = "alphabetic"
    let link = this.data.link_label || ""
    while (ctx.measureText(link).width > W - 160 && link.length > 6) link = link.slice(0, -2) + "…"
    ctx.fillText(link, W / 2, H - 76)
  }

  release() {
    for (const c of [this.canvas, this.background, this.glowSprite, this.header, this.footer, this.intro, this.outro, ...this.cards]) {
      if (c) { c.width = 0; c.height = 0 }
    }
    this.cards = []
  }
}

// ── Encoding ──

// Makes the video. options: { theme, assets, replies, onProgress(0..1), signal }
// Returns { blob, type, ext, duration, method }.
export async function makeThreadVideo(data, options) {
  const scene = new Scene(data, options)
  try {
    const codec = await supportedCodec()
    if (codec) {
      try { return await encodeWithWebCodecs(scene, codec, options) } catch (error) {
        if (error?.name === "AbortError") throw error
        console.warn("WebCodecs encoding failed, recording instead", error)
      }
    }
    return await recordInRealTime(scene, options)
  } finally {
    scene.release()
  }
}

function aborted(signal) {
  if (signal?.aborted) throw new DOMException("Stopped", "AbortError")
}

async function encodeWithWebCodecs(scene, codec, { onProgress, signal }) {
  const target = new ArrayBufferTarget()
  const muxer = new Muxer({ target, video: { codec: "avc", width: W, height: H, frameRate: FPS }, fastStart: "in-memory", firstTimestampBehavior: "offset" })
  let failure = null
  const encoder = new VideoEncoder({
    output: (chunk, meta) => muxer.addVideoChunk(chunk, meta),
    error: (e) => { failure = e }
  })
  encoder.configure(encoderConfig(codec))
  const frames = Math.round(scene.duration * FPS)
  const frameUs = 1e6 / FPS
  try {
    for (let f = 0; f < frames; f++) {
      aborted(signal)
      if (failure) throw failure
      scene.draw(f / FPS)
      const frame = new VideoFrame(scene.canvas, { timestamp: Math.round(f * frameUs), duration: Math.round(frameUs) })
      encoder.encode(frame, { keyFrame: f % (FPS * 2) === 0 })
      frame.close()
      while (encoder.encodeQueueSize > 4) {
        if (failure) throw failure
        await new Promise(r => setTimeout(r, 2))
      }
      onProgress?.((f + 1) / frames * 0.97)
      await yieldToPage()
    }
    await encoder.flush()
    if (failure) throw failure
    muxer.finalize()
    onProgress?.(1)
    return { blob: new Blob([target.buffer], { type: "video/mp4" }), type: "video/mp4", ext: "mp4", duration: frames / FPS, method: "webcodecs" }
  } finally {
    if (encoder.state !== "closed") encoder.close()
  }
}

async function recordInRealTime(scene, { onProgress, signal }) {
  const rec = recorderType()
  if (!rec) throw new Error("This browser can't make videos")
  scene.draw(0)
  const stream = scene.canvas.captureStream(FPS)
  const recorder = new MediaRecorder(stream, { mimeType: rec.type, videoBitsPerSecond: BITRATE })
  const parts = []
  recorder.ondataavailable = (e) => { if (e.data?.size) parts.push(e.data) }
  const stopped = new Promise(resolve => { recorder.onstop = resolve })
  recorder.start(1000)
  const start = performance.now()
  try {
    await new Promise((resolve, reject) => {
      const tick = () => {
        if (signal?.aborted) return reject(new DOMException("Stopped", "AbortError"))
        const t = (performance.now() - start) / 1000
        scene.draw(Math.min(t, scene.duration))
        onProgress?.(Math.min(1, t / scene.duration))
        if (t >= scene.duration) resolve()
        else requestAnimationFrame(tick)
      }
      requestAnimationFrame(tick)
    })
  } finally {
    if (recorder.state !== "inactive") recorder.stop()
    await stopped
    stream.getTracks().forEach(track => track.stop())
  }
  aborted(signal)
  const type = rec.type.split(";")[0]
  return { blob: new Blob(parts, { type }), type, ext: rec.ext, duration: scene.duration, method: "recorder" }
}
