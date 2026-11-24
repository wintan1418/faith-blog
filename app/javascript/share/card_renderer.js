// Draws a breath (or one reply of a shared thread) as a social post card on a
// canvas: Story 1080x1920, Square 1080x1080 or Portrait 1080x1350, light or
// dark, in the author's accent colour. Loaded on demand by the share sheet.
//
// Text: Unicode "mathematical" letters (𝗪𝗵𝗼 𝗜𝘀…) are drawn as real Inter
// bold/italic, so styled titles look right on every phone whatever fonts it
// has; emoji come from the system emoji font through the canvas font stack.

export const FORMATS = {
  story:    { width: 1080, height: 1920, label: "Story",    hint: "WhatsApp · Instagram status" },
  square:   { width: 1080, height: 1080, label: "Square",   hint: "Feed post" },
  portrait: { width: 1080, height: 1350, label: "Portrait", hint: "LinkedIn · X" }
}

const STACK = `Inter, system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif`

const THEMES = {
  light: {
    frame: ["#f6f2e9", "#ebe5d8"], card: "#ffffff", ink: "#14201b", soft: "#2c3833", muted: "#62706a",
    line: "rgba(20, 32, 27, 0.10)", shadow: "rgba(40, 34, 14, 0.16)", chip: "rgba(20, 32, 27, 0.06)", glow: 0.30
  },
  dark: {
    frame: ["#07100d", "#0e1914"], card: "#121c18", ink: "#eef4f1", soft: "#d3ddd8", muted: "#97a69f",
    line: "rgba(255, 255, 255, 0.10)", shadow: "rgba(0, 0, 0, 0.55)", chip: "rgba(255, 255, 255, 0.07)", glow: 0.26
  }
}

// The Brethreign "B" (shared/_logomark.html.erb): two soft rings and the solid mark.
const LOGO_W = 670.46, LOGO_H = 1024
const LOGO = [
  [0.2, "M366.07,509.84c-2.31.78-4.62,1.54-7.19,2.31,12.08,2.06,23.65,4.38,34.71,7.21,18.25,4.12,35.21,8.74,50.9,13.88,48.58,15.43,86.11,33.93,113.63,55.27,20.05,15.43,35.74,31.37,47.05,47.81,4.37,6.18,8.22,12.6,11.31,19.03,11.31,23.13,16.96,46.27,16.96,68.89,0,40.62-11.82,78.93-35.99,114.92-24.41,35.99-56.04,67.87-95.38,95.38-39.33,27.25-82.01,49.11-127.76,65.3-7.21,2.57-14.4,4.88-21.6,6.94-38.3,11.31-75.32,17.22-111.05,17.22-9.77,0-19.02-.77-28.28-2.82-26.74-4.88-51.15-17.22-73.52-37.02-29.83-26.49-55.02-62.47-76.09-107.98-19.03-41.12-33.68-87.92-44.22-140.36-1.03-5.15-2.06-10.54-3.09-15.94C5.4,661.27,0,600.08,0,536.84c0-9,0-17.74.25-26.22v-1.81c.26-27.24,1.03-52.95,2.57-77.37,1.8-32.13,4.88-64.02,9-94.86,2.57-17.23,5.15-34.96,7.97-53.74,10.53-52.18,25.19-98.71,43.96-139.59,21.08-45.5,46.27-81.49,76.09-107.98.23-.2.45-.4.68-.59C170.28,8.89,210.28-2.51,249.54.46c30.29,2.29,59.74,5.62,88.25,9.89,5.15.77,10.03,1.53,14.91,2.31,60.42,9.77,113.38,24.93,159.39,44.74,49.62,21.33,88.43,48.58,116.45,82.26,27.77,33.68,41.91,74.04,41.91,121.6,0,28.02-12.34,58.87-37.03,91.52-7.71,10.28-17.22,20.56-28.27,30.34-24.43,22.62-56.81,44.73-97.43,66.83-31.88,17.22-69.93,33.94-114.14,50.14-8.75,3.09-18,6.43-27.52,9.77Z"],
  [0.6, "M360.93,510.2c-1.92.65-3.85,1.29-5.99,1.92,10.06,1.72,19.71,3.65,28.92,6,15.21,3.43,29.34,7.28,42.42,11.57,40.48,12.86,71.76,28.27,94.69,46.06,16.71,12.86,29.78,26.14,39.21,39.84,3.64,5.15,6.85,10.5,9.42,15.86,9.42,19.28,14.13,38.56,14.13,57.41,0,33.85-9.85,65.78-29.99,95.77-20.35,29.99-46.7,56.56-79.48,79.48-32.77,22.71-68.34,40.92-106.47,54.42-6,2.14-12,4.07-18,5.78-31.92,9.42-62.76,14.35-92.54,14.35-8.14,0-15.85-.64-23.57-2.35-22.28-4.07-42.63-14.35-61.27-30.85-24.85-22.07-45.85-52.06-63.41-89.98-15.86-34.27-28.07-73.27-36.85-116.97-.86-4.29-1.72-8.79-2.57-13.28-9.21-48.84-13.7-99.83-13.7-152.53,0-7.5,0-14.78.21-21.85v-1.51c.22-22.7.86-44.12,2.14-64.48,1.5-26.78,4.07-53.35,7.5-79.05,2.14-14.36,4.29-29.13,6.64-44.78,8.78-43.48,20.99-82.26,36.63-116.32,17.56-37.92,38.56-67.91,63.41-89.98.19-.16.38-.33.57-.49,24.79-21.5,58.12-31,90.84-28.52,25.24,1.91,49.79,4.68,73.54,8.24,4.29.64,8.36,1.28,12.43,1.92,50.35,8.14,94.48,20.77,132.83,37.28,41.35,17.77,73.69,40.48,97.04,68.55,23.14,28.07,34.93,61.7,34.93,101.33,0,23.35-10.28,49.06-30.86,76.27-6.42,8.57-14.35,17.13-23.56,25.28-20.36,18.85-47.34,37.27-81.19,55.69-26.57,14.35-58.28,28.29-95.12,41.78-7.29,2.57-15,5.36-22.93,8.14Z"],
  [1, "M355.79,510.56c-1.54.52-3.08,1.03-4.8,1.54,8.05,1.37,15.77,2.92,23.14,4.8,12.17,2.74,23.47,5.82,33.93,9.26,32.39,10.28,57.41,22.62,75.75,36.85,13.36,10.28,23.82,20.91,31.36,31.88,2.91,4.12,5.48,8.4,7.54,12.69,7.54,15.42,11.31,30.85,11.31,45.93,0,27.08-7.88,52.62-23.99,76.61-16.28,23.99-37.36,45.25-63.58,63.58-26.22,18.17-54.67,32.74-85.17,43.53-4.8,1.72-9.6,3.26-14.4,4.63-25.53,7.54-50.21,11.48-74.04,11.48-6.51,0-12.68-.51-18.85-1.88-17.82-3.26-34.1-11.48-49.01-24.68-19.88-17.66-36.68-41.65-50.73-71.99-12.69-27.42-22.45-58.61-29.48-93.58-.69-3.43-1.37-7.03-2.06-10.63-7.36-39.07-10.96-79.86-10.96-122.02,0-6,0-11.82.17-17.48v-1.21c.18-18.16.69-35.3,1.72-51.58,1.2-21.42,3.26-42.68,6-63.24,1.72-11.49,3.43-23.31,5.31-35.83,7.02-34.79,16.8-65.81,29.31-93.06,14.05-30.34,30.85-54.33,50.73-71.99.15-.13.3-.26.45-.39,19.83-17.2,46.5-24.8,72.67-22.82,20.19,1.53,39.83,3.75,58.84,6.59,3.43.51,6.69,1.02,9.94,1.54,40.28,6.51,75.58,16.62,106.26,29.83,33.08,14.22,58.96,32.39,77.63,54.84,18.51,22.45,27.94,49.36,27.94,81.07,0,18.68-8.23,39.25-24.69,61.01-5.14,6.85-11.48,13.71-18.85,20.23-16.28,15.08-37.88,29.82-64.96,44.55-21.26,11.48-46.62,22.63-76.09,33.42-5.83,2.06-12,4.28-18.34,6.51Z"]
]

const ICONS = {
  heart:   "M12 20.5s-7.2-4.4-9.2-8.8C1.4 8.4 3.4 4.8 6.9 4.8c2 0 3.6 1.1 5.1 2.9 1.5-1.8 3.1-2.9 5.1-2.9 3.5 0 5.5 3.6 4.1 6.9-2 4.4-9.2 8.8-9.2 8.8z",
  comment: "M4.5 5h15A1.5 1.5 0 0 1 21 6.5v9a1.5 1.5 0 0 1-1.5 1.5H10l-4.5 3.6V17h-1A1.5 1.5 0 0 1 3 15.5v-9A1.5 1.5 0 0 1 4.5 5z",
  repost:  "M7 7h10.5a2.5 2.5 0 0 1 2.5 2.5V12M17 17H6.5A2.5 2.5 0 0 1 4 14.5V12M15.5 4.5 18 7l-2.5 2.5M8.5 19.5 6 17l2.5-2.5",
  seed:    "M12 21v-8M12 13c0-4 2.6-6.6 7-7 0 4.3-2.8 7-7 7zM12 15.5c0-3.2-2-5.2-5.5-5.5 0 3.4 2.2 5.5 5.5 5.5z",
  person:  "M12 12.5a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4.5 20.5c0-4.1 3.4-7.3 7.5-7.3s7.5 3.2 7.5 7.3",
  check:   "M7.5 12.5l3 3 6-6.5"
}

// ── Text: runs of plain / bold / italic, with styled Unicode letters mapped back ──

// [first, last, bold, italic] for the Mathematical Alphanumeric Symbols block.
const MATH_STYLES = [
  [0x1D400, 0x1D433, true, false], [0x1D434, 0x1D467, false, true], [0x1D468, 0x1D49B, true, true],
  [0x1D49C, 0x1D4CF, false, true], [0x1D4D0, 0x1D503, true, true], [0x1D504, 0x1D537, false, false],
  [0x1D538, 0x1D56B, true, false], [0x1D56C, 0x1D59F, true, false], [0x1D5A0, 0x1D5D3, false, false],
  [0x1D5D4, 0x1D607, true, false], [0x1D608, 0x1D63B, false, true], [0x1D63C, 0x1D66F, true, true],
  [0x1D670, 0x1D6A3, false, false], [0x1D6A8, 0x1D6E1, true, false], [0x1D6E2, 0x1D71B, false, true],
  [0x1D71C, 0x1D755, true, true], [0x1D756, 0x1D78F, true, false], [0x1D790, 0x1D7C9, true, true],
  [0x1D7CE, 0x1D7D7, true, false], [0x1D7D8, 0x1D7E1, false, false], [0x1D7E2, 0x1D7EB, false, false],
  [0x1D7EC, 0x1D7F5, true, false], [0x1D7F6, 0x1D7FF, false, false]
]

function mathStyle(cp) {
  if (cp < 0x1D400 || cp > 0x1D7FF) return null
  for (const [a, b, bold, italic] of MATH_STYLES) if (cp >= a && cp <= b) return { bold, italic }
  return { bold: false, italic: false }
}

// "𝗪𝗵𝗼 is" → [{ text: "Who", bold: true }, { text: " is" }]
export function toRuns(text, base = {}) {
  const runs = []
  const push = (ch, bold, italic) => {
    const last = runs[runs.length - 1]
    if (last && last.bold === bold && last.italic === italic) last.text += ch
    else runs.push({ text: ch, bold, italic })
  }
  for (const ch of String(text || "")) {
    const style = mathStyle(ch.codePointAt(0))
    if (style) push(ch.normalize("NFKC"), base.bold || style.bold, base.italic || style.italic)
    else push(ch, !!base.bold, !!base.italic)
  }
  return runs
}

export function plainText(text) {
  return toRuns(text).map(r => r.text).join("")
}

const graphemes = (s) => {
  if (typeof Intl !== "undefined" && Intl.Segmenter) {
    return [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(s)].map(x => x.segment)
  }
  return [...s]
}

function fontFor(style, size, weight) {
  const w = style.bold ? Math.max(weight, 700) : weight
  return `${style.italic ? "italic " : ""}${w} ${size}px ${STACK}`
}

// Splits text into words, each a list of styled pieces, plus hard line breaks.
function tokenize(text, base) {
  const tokens = []
  const paragraphs = String(text || "").split("\n")
  paragraphs.forEach((para, i) => {
    if (i > 0) tokens.push({ br: true, blank: para.trim() === "" })
    let word = []
    let pendingSpace = false
    for (const run of toRuns(para, base)) {
      const parts = run.text.split(/(\s+)/)
      for (const part of parts) {
        if (part === "") continue
        if (/^\s+$/.test(part)) {
          if (word.length) { tokens.push({ pieces: word, space: pendingSpace }); word = [] }
          pendingSpace = true
        } else {
          if (!word.length && tokens.length && !tokens[tokens.length - 1].br) pendingSpace = pendingSpace || false
          word.push({ text: part, bold: run.bold, italic: run.italic })
        }
      }
    }
    if (word.length) tokens.push({ pieces: word, space: pendingSpace })
  })
  return tokens
}

function measurePieces(ctx, pieces, size, weight) {
  let w = 0
  for (const p of pieces) { ctx.font = fontFor(p, size, weight); w += ctx.measureText(p.text).width }
  return w
}

// Lays text out into lines of styled pieces no wider than maxWidth.
export function wrap(ctx, text, { size, weight = 400, maxWidth, base = {} }) {
  ctx.font = fontFor({}, size, weight)
  const spaceW = ctx.measureText(" ").width
  const lines = []
  let line = { pieces: [], width: 0, gapBefore: false }
  const flush = (gap = false) => { lines.push(line); line = { pieces: [], width: 0, gapBefore: gap } }

  for (const token of tokenize(text, base)) {
    if (token.br) {
      if (line.pieces.length) flush(token.blank)
      else if (token.blank && lines.length) line.gapBefore = true
      continue
    }
    let width = measurePieces(ctx, token.pieces, size, weight)
    const lead = line.pieces.length ? spaceW : 0
    if (line.pieces.length && line.width + lead + width > maxWidth) flush()

    // A word wider than the whole line breaks between characters.
    if (width > maxWidth) {
      for (const piece of token.pieces) {
        for (const g of graphemes(piece.text)) {
          ctx.font = fontFor(piece, size, weight)
          const gw = ctx.measureText(g).width
          if (line.width + gw > maxWidth && line.pieces.length) flush()
          line.pieces.push({ ...piece, text: g })
          line.width += gw
        }
      }
      continue
    }
    if (line.pieces.length) { line.pieces.push({ text: " ", bold: false, italic: false }); line.width += spaceW }
    token.pieces.forEach(p => line.pieces.push({ ...p }))
    line.width += width
  }
  if (line.pieces.length) lines.push(line)
  return lines
}

function linesHeight(lines, lh) {
  return lines.reduce((h, l, i) => h + lh + (l.gapBefore && i > 0 ? lh * 0.45 : 0), 0)
}

function drawLines(ctx, lines, x, y, { size, weight = 400, lh, color }) {
  ctx.fillStyle = color
  ctx.textBaseline = "alphabetic"
  ctx.textAlign = "left"
  let cy = y
  lines.forEach((line, i) => {
    if (line.gapBefore && i > 0) cy += lh * 0.45
    let cx = x
    const baseline = cy + lh * 0.5 + size * 0.36
    for (const p of line.pieces) {
      ctx.font = fontFor(p, size, weight)
      ctx.fillText(p.text, cx, baseline)
      cx += ctx.measureText(p.text).width
    }
    cy += lh
  })
  return cy
}

function ellipsize(ctx, line, maxWidth, size, weight) {
  const out = { ...line, pieces: line.pieces.map(p => ({ ...p })) }
  const width = () => measurePieces(ctx, out.pieces, size, weight)
  const tail = { text: "…", bold: false, italic: false }
  const tailW = measurePieces(ctx, [tail], size, weight)
  // Drop whole words first; only a single long word gets cut mid-way.
  while (out.pieces.length > 2 && width() + tailW > maxWidth) {
    out.pieces.pop()
    while (out.pieces.length > 1 && out.pieces[out.pieces.length - 1].text !== " ") out.pieces.pop()
  }
  while (out.pieces.length && width() + tailW > maxWidth) {
    const last = out.pieces[out.pieces.length - 1]
    const chars = graphemes(last.text)
    chars.pop()
    if (chars.length) last.text = chars.join("")
    else out.pieces.pop()
  }
  while (out.pieces.length && /^\s*$/.test(out.pieces[out.pieces.length - 1].text)) out.pieces.pop()
  const last = out.pieces[out.pieces.length - 1]
  if (last) last.text = last.text.replace(/[\s,;:.\-–—]+$/u, "")
  out.pieces.push(tail)
  return out
}

// Biggest size in `sizes` whose lines fit maxHeight; at the smallest size the
// text is cut to fit and marked `clipped`.
export function fitText(ctx, text, { sizes, weight = 400, maxWidth, maxHeight, lineHeight = 1.4, base, reserveLines = 0, forceClip = false }) {
  for (const size of sizes) {
    const lh = Math.round(size * lineHeight)
    const lines = wrap(ctx, text, { size, weight, maxWidth, base })
    const h = linesHeight(lines, lh)
    if (h <= maxHeight && !(forceClip && size !== sizes[sizes.length - 1])) {
      if (!forceClip) return { lines, size, lh, height: h, clipped: false }
    }
  }
  const size = sizes[sizes.length - 1]
  const lh = Math.round(size * lineHeight)
  const all = wrap(ctx, text, { size, weight, maxWidth, base })
  const room = maxHeight - reserveLines * lh
  const lines = []
  for (const line of all) {
    if (linesHeight([...lines, line], lh) > room) break
    lines.push(line)
  }
  const clipped = forceClip || lines.length < all.length
  if (clipped && lines.length && lines.length < all.length) lines[lines.length - 1] = ellipsize(ctx, lines[lines.length - 1], maxWidth, size, weight)
  return { lines, size, lh, height: linesHeight(lines, lh), clipped }
}

// ── Shapes ──

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath()
  if (ctx.roundRect) { ctx.roundRect(x, y, w, h, r); return }
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

function drawLogo(ctx, x, y, height, color) {
  const scale = height / LOGO_H
  ctx.save()
  ctx.translate(x, y)
  ctx.scale(scale, scale)
  ctx.fillStyle = color
  for (const [alpha, d] of LOGO) { ctx.globalAlpha = alpha; ctx.fill(new Path2D(d)) }
  ctx.restore()
  return LOGO_W * scale
}

function drawIcon(ctx, name, x, y, size, color, { fill = false, width = 2 } = {}) {
  ctx.save()
  ctx.translate(x, y)
  ctx.scale(size / 24, size / 24)
  const path = new Path2D(ICONS[name])
  if (fill) { ctx.fillStyle = color; ctx.fill(path) }
  ctx.strokeStyle = color
  ctx.lineWidth = width
  ctx.lineCap = "round"
  ctx.lineJoin = "round"
  ctx.stroke(path)
  ctx.restore()
}

function drawQR(ctx, rows, x, y, size, ink) {
  const n = rows.length
  const quiet = 2
  const cell = size / (n + quiet * 2)
  ctx.fillStyle = "#ffffff"
  roundRect(ctx, x, y, size, size, Math.round(size * 0.08))
  ctx.fill()
  ctx.fillStyle = ink
  for (let r = 0; r < n; r++) {
    const row = rows[r]
    for (let c = 0; c < n; c++) {
      if (row.charCodeAt(c) === 49) {
        ctx.fillRect(Math.floor(x + (c + quiet) * cell), Math.floor(y + (r + quiet) * cell), Math.ceil(cell), Math.ceil(cell))
      }
    }
  }
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

function hexToRgba(hex, alpha) {
  const h = String(hex || "#34d399").replace("#", "")
  const n = parseInt(h.length === 3 ? h.split("").map(c => c + c).join("") : h, 16)
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`
}

function formatCount(n) {
  n = Number(n) || 0
  if (n < 1000) return String(n)
  if (n < 10000) return `${(n / 1000).toFixed(1).replace(/\.0$/, "")}k`
  return `${Math.floor(n / 1000)}k`
}

function drawPill(ctx, text, x, y, { size, height, color, bg, weight = 700, padX }) {
  ctx.font = `${weight} ${size}px ${STACK}`
  const w = ctx.measureText(text).width + padX * 2
  ctx.fillStyle = bg
  roundRect(ctx, x, y, w, height, height / 2)
  ctx.fill()
  ctx.fillStyle = color
  ctx.textBaseline = "middle"
  ctx.textAlign = "left"
  ctx.fillText(text, x + padX, y + height / 2 + 1)
  return w
}

// ── Assets ──

export function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.crossOrigin = "anonymous"
    img.decoding = "async"
    const timer = setTimeout(() => reject(new Error("image timeout")), 8000)
    img.onload = () => { clearTimeout(timer); resolve(img) }
    img.onerror = () => { clearTimeout(timer); reject(new Error("image failed")) }
    img.src = src
  })
}

// A small cross-origin copy first (needs CORS for the canvas), then our own copy.
async function loadEither(source) {
  if (!source) return null
  for (const src of [source.url, source.fallback]) {
    if (!src) continue
    try { return await loadImage(src) } catch { /* try the next */ }
  }
  return null
}

const assetCache = new Map()
function cached(key, load) {
  if (!key) return Promise.resolve(null)
  if (!assetCache.has(key)) assetCache.set(key, load().catch(() => null))
  return assetCache.get(key)
}

export async function loadAssets(data) {
  const fonts = document.fonts
  if (fonts?.load) {
    await Promise.all(["400 32px Inter", "600 32px Inter", "700 32px Inter", "italic 400 32px Inter"]
      .map(f => fonts.load(f).catch(() => null)))
  }
  const avatars = {}
  const people = [data.author, ...(data.reply_candidates || []).map(r => r.author)]
  await Promise.all(people.map(async (a) => {
    const src = a?.avatar_url
    if (!src || avatars[a.username]) return
    avatars[a.username] = await cached(src.url || src.fallback, () => loadEither(src))
  }))
  const image = data.image ? await cached(data.image.url || data.image.fallback, () => loadEither(data.image)) : null
  return { avatars, image }
}

// ── The card ──

function sizesFor(format) {
  if (format === "story") {
    return { margin: 64, pad: 64, radius: 48, avatar: 112, name: 42, handle: 31, title: [78, 72, 66, 60, 54, 48, 44], body: [50, 46, 42, 39, 36, 33, 31],
             reply: [56, 52, 48, 44, 40, 37, 34], meta: 31, icon: 36, qr: 236, imgMax: 640, imgMin: 300, label: 26 }
  }
  if (format === "square") {
    return { margin: 48, pad: 52, radius: 40, avatar: 88, name: 36, handle: 27, title: [58, 52, 47, 43, 39, 35], body: [38, 35, 32, 30, 28, 26],
             reply: [44, 40, 36, 33, 30, 28], meta: 27, icon: 30, qr: 150, imgMax: 330, imgMin: 190, label: 22 }
  }
  return { margin: 52, pad: 56, radius: 44, avatar: 96, name: 38, handle: 28, title: [64, 58, 52, 47, 43, 39], body: [42, 39, 36, 33, 31, 29],
           reply: [48, 44, 40, 37, 34, 31], meta: 28, icon: 32, qr: 170, imgMax: 470, imgMin: 220, label: 23 }
}

// opts: { format, theme, assets, reply (a reply object, for thread cards), index, total }
export function renderCard(data, opts) {
  const format = FORMATS[opts.format] ? opts.format : "story"
  const { width: W, height: H } = FORMATS[format]
  const T = THEMES[opts.theme] || THEMES.light
  const S = sizesFor(format)
  const accent = data.accent || "#34d399"
  const accentDeep = data.accent_deep || accent
  const accentText = opts.theme === "dark" ? accent : accentDeep
  const reply = opts.reply || null
  const person = reply ? reply.author : data.author
  const avatarImg = person && !person.anonymous ? opts.assets?.avatars?.[person.username] : null
  const postImage = reply ? null : opts.assets?.image

  const canvas = document.createElement("canvas")
  canvas.width = W
  canvas.height = H
  const ctx = canvas.getContext("2d")

  // Frame: the theme's ground with the author's colour glowing in.
  const bg = ctx.createLinearGradient(0, 0, W, H)
  bg.addColorStop(0, T.frame[0])
  bg.addColorStop(1, T.frame[1])
  ctx.fillStyle = bg
  ctx.fillRect(0, 0, W, H)
  const glow = (x, y, r, color, a) => {
    const g = ctx.createRadialGradient(x, y, 0, x, y, r)
    g.addColorStop(0, hexToRgba(color, a))
    g.addColorStop(1, hexToRgba(color, 0))
    ctx.fillStyle = g
    ctx.fillRect(0, 0, W, H)
  }
  glow(W, 0, W * 0.95, accent, T.glow)
  glow(0, H, W * 0.85, accentDeep, T.glow * 0.55)

  const cardX = S.margin
  const cardW = W - S.margin * 2
  const innerX = cardX + S.pad
  const innerW = cardW - S.pad * 2

  // Story: the brand sits above the card and the QR footer below it.
  let areaTop = S.margin
  let areaBottom = H - S.margin
  const story = format === "story"
  if (story) {
    const logoH = 76
    ctx.font = `700 46px ${STACK}`
    const wordW = ctx.measureText("Brethreign").width
    const totalW = LOGO_W * (logoH / LOGO_H) + 18 + wordW
    const lx = (W - totalW) / 2
    const lw = drawLogo(ctx, lx, 118, logoH, accentText)
    ctx.fillStyle = T.ink
    ctx.textBaseline = "middle"
    ctx.textAlign = "left"
    ctx.fillText("Brethreign", lx + lw + 18, 118 + logoH / 2 + 2)
    areaTop = 250
    areaBottom = H - 430
  }

  // Measure everything that isn't flexible.
  const headerH = S.avatar
  const gap = Math.round(S.pad * 0.5)
  const chips = []
  if (opts.total > 1) chips.push({ kind: "count" })
  const label = reply ? null : data.label
  const series = reply ? null : data.series
  const contextLine = reply ? `Replying to ${data.author.anonymous ? "Anonymous" : "@" + data.author.username}` : null
  const metaH = reply || data.counts ? Math.round(S.meta * 1.6) : 0
  const footerH = story ? 0 : S.qr + Math.round(S.pad * 0.6)
  const tagH = Math.round(S.label * 1.9)

  let fixed = S.pad + headerH + gap + metaH + S.pad + footerH
  if (label || series) fixed += tagH + Math.round(gap * 0.8)
  if (contextLine) fixed += Math.round(S.meta * 1.5) + Math.round(gap * 0.5)
  const maxCardH = areaBottom - areaTop
  let room = maxCardH - fixed - gap

  // Title, body and photo share what's left.
  const title = reply ? "" : (data.title || "")
  const bodyText = reply ? reply.text : (data.text || "")
  const truncatedAtSource = reply ? reply.truncated : data.truncated
  let titleFit = null
  if (title) {
    titleFit = fitText(ctx, title, { sizes: S.title, weight: 700, maxWidth: innerW, maxHeight: Math.max(S.title[0] * 1.2, room * 0.4), lineHeight: 1.18, base: { bold: true } })
    room -= titleFit.height + Math.round(gap * 0.7)
  }

  let imgH = 0
  if (postImage) {
    const natural = innerW / (postImage.naturalWidth / postImage.naturalHeight)
    const bodyNeed = bodyText ? fitText(ctx, bodyText, { sizes: [S.body[0]], maxWidth: innerW, maxHeight: 1e6, lineHeight: 1.42 }).height : 0
    const wanted = Math.min(S.imgMax, natural)
    const leftForImage = room - Math.min(bodyNeed, room * 0.5) - gap
    imgH = Math.max(Math.min(wanted, leftForImage), Math.min(S.imgMin, natural))
    if (imgH > room - S.body[S.body.length - 1] * 3) imgH = Math.max(0, Math.min(imgH, room - S.body[S.body.length - 1] * 3))
    if (imgH < 120) imgH = 0
    else room -= imgH + gap
  }

  const readMore = "Read the rest on Brethreign"
  let bodyFit = null
  if (bodyText) {
    const sizes = reply ? S.reply : (title ? S.body : S.reply)
    bodyFit = fitText(ctx, bodyText, { sizes, maxWidth: innerW, maxHeight: Math.max(room, sizes[sizes.length - 1] * 1.42), lineHeight: 1.42, reserveLines: 1, forceClip: false })
    if (truncatedAtSource && !bodyFit.clipped) {
      // The server already shortened it: say so, even if what's left fits.
      bodyFit = { ...bodyFit, clipped: true }
    }
    if (bodyFit.clipped) bodyFit.height += bodyFit.lh
  }

  // The card is as tall as its content, centred in its area.
  const contentH = (titleFit ? titleFit.height + Math.round(gap * 0.7) : 0) + (bodyFit ? bodyFit.height : 0) + (imgH ? imgH + gap : 0)
  const cardH = Math.min(maxCardH, fixed + contentH + gap)
  const cardY = Math.round(areaTop + (maxCardH - cardH) * (story ? 0.4 : 0.5))

  ctx.save()
  ctx.shadowColor = T.shadow
  ctx.shadowBlur = 60
  ctx.shadowOffsetY = 18
  ctx.fillStyle = T.card
  roundRect(ctx, cardX, cardY, cardW, cardH, S.radius)
  ctx.fill()
  ctx.restore()
  ctx.strokeStyle = T.line
  ctx.lineWidth = 2
  roundRect(ctx, cardX, cardY, cardW, cardH, S.radius)
  ctx.stroke()
  // A thin band of the author's colour along the top edge.
  ctx.save()
  roundRect(ctx, cardX, cardY, cardW, cardH, S.radius)
  ctx.clip()
  ctx.fillStyle = accent
  ctx.fillRect(cardX, cardY, cardW, 10)
  ctx.restore()

  let y = cardY + S.pad

  // Header: avatar, name + badge, @handle · date, and n/N on thread cards.
  const ax = innerX
  if (person && !person.anonymous && avatarImg) {
    ctx.save()
    ctx.beginPath()
    ctx.arc(ax + S.avatar / 2, y + S.avatar / 2, S.avatar / 2, 0, Math.PI * 2)
    ctx.clip()
    coverImage(ctx, avatarImg, ax, y, S.avatar, S.avatar, 0)
    ctx.restore()
  } else if (person && !person.anonymous) {
    ctx.fillStyle = accent
    ctx.beginPath()
    ctx.arc(ax + S.avatar / 2, y + S.avatar / 2, S.avatar / 2, 0, Math.PI * 2)
    ctx.fill()
    ctx.fillStyle = "#06281c"
    ctx.font = `700 ${Math.round(S.avatar * 0.42)}px ${STACK}`
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillText(person.initial || "?", ax + S.avatar / 2, y + S.avatar / 2 + 2)
  } else {
    ctx.fillStyle = T.chip
    ctx.beginPath()
    ctx.arc(ax + S.avatar / 2, y + S.avatar / 2, S.avatar / 2, 0, Math.PI * 2)
    ctx.fill()
    const s = S.avatar * 0.5
    drawIcon(ctx, "person", ax + (S.avatar - s) / 2, y + (S.avatar - s) / 2, s, T.muted, { width: 1.9 })
  }

  let countW = 0
  if (opts.total > 1) {
    ctx.font = `700 ${S.label}px ${STACK}`
    const txt = `${opts.index}/${opts.total}`
    countW = ctx.measureText(txt).width + S.label * 1.6
    drawPill(ctx, txt, innerX + innerW - countW, y + (headerH - tagH) / 2, { size: S.label, height: tagH, color: accentText, bg: hexToRgba(accent, 0.16), padX: S.label * 0.8 })
  }

  const nx = ax + S.avatar + Math.round(S.avatar * 0.22)
  const nameMax = innerX + innerW - nx - (countW ? countW + 16 : 0)
  const name = person?.anonymous ? (person.name || "Anonymous") : (person?.name || "")
  ctx.textAlign = "left"
  ctx.textBaseline = "alphabetic"
  const nameFit = fitText(ctx, name, { sizes: [S.name, S.name - 4, S.name - 8], weight: 700, maxWidth: nameMax - S.name * 1.4, maxHeight: S.name * 1.3, lineHeight: 1.2 })
  const nameBase = y + headerH / 2 - S.name * 0.1
  const nameMid = nameBase - nameFit.size * 0.36
  drawLines(ctx, nameFit.lines.slice(0, 1), nx, nameBase - nameFit.lh * 0.5 - nameFit.size * 0.36, { size: nameFit.size, weight: 700, lh: nameFit.lh, color: T.ink })
  const nameW = nameFit.lines[0] ? nameFit.lines[0].width : 0
  if (person && !person.anonymous && person.verified) {
    const bs = Math.round(S.name * 0.86)
    const bx = nx + nameW + 12
    const by = nameMid - bs / 2
    ctx.fillStyle = accentDeep
    ctx.beginPath()
    ctx.arc(bx + bs / 2, by + bs / 2, bs / 2, 0, Math.PI * 2)
    ctx.fill()
    drawIcon(ctx, "check", bx, by, bs, "#ffffff", { width: 3 })
  }
  if (person && !person.anonymous && person.founder) {
    const offset = nx + nameW + 12 + (person.verified ? Math.round(S.name * 0.86) + 10 : 0)
    drawPill(ctx, "Founder", offset, nameMid - Math.round(S.label * 1.6) / 2, { size: Math.round(S.label * 0.85), height: Math.round(S.label * 1.6), color: opts.theme === "dark" ? "#f3d9a4" : "#8a5a0b", bg: opts.theme === "dark" ? "rgba(212,168,90,0.20)" : "#fbf3e2", padX: S.label * 0.6 })
  }
  const when = reply ? reply.date : data.date
  const handle = [person && !person.anonymous ? `@${person.username}` : null, when].filter(Boolean).join(" · ")
  ctx.font = `400 ${S.handle}px ${STACK}`
  ctx.fillStyle = T.muted
  ctx.textBaseline = "alphabetic"
  ctx.fillText(handle, nx, y + headerH / 2 + S.handle * 1.22)
  y += headerH + gap

  if (contextLine) {
    ctx.font = `500 ${S.meta}px ${STACK}`
    ctx.fillStyle = T.muted
    ctx.textBaseline = "top"
    let ctxText = contextLine
    if (data.title) ctxText += ` · ${plainText(data.title)}`
    while (ctx.measureText(ctxText).width > innerW && ctxText.length > 4) ctxText = ctxText.slice(0, -2).trimEnd() + "…"
    if (ctxText.endsWith("……")) ctxText = ctxText.slice(0, -1)
    ctx.fillText(ctxText, innerX, y)
    y += Math.round(S.meta * 1.5) + Math.round(gap * 0.5)
  }

  if (label || series) {
    let tx = innerX
    if (label) tx += drawPill(ctx, label, tx, y, { size: S.label, height: tagH, color: accentText, bg: hexToRgba(accent, 0.15), padX: S.label * 0.8 }) + 12
    if (series) {
      ctx.font = `700 ${S.label}px ${STACK}`
      let s = series
      while (ctx.measureText(s).width + S.label * 1.6 > innerX + innerW - tx && s.length > 4) s = s.slice(0, -2).trimEnd() + "…"
      drawPill(ctx, s, tx, y, { size: S.label, height: tagH, color: T.soft, bg: T.chip, padX: S.label * 0.8 })
    }
    y += tagH + Math.round(gap * 0.8)
  }

  if (titleFit) {
    drawLines(ctx, titleFit.lines, innerX, y, { size: titleFit.size, weight: 700, lh: titleFit.lh, color: T.ink })
    y += titleFit.height + Math.round(gap * 0.7)
  }

  if (bodyFit) {
    const textH = bodyFit.clipped ? bodyFit.height - bodyFit.lh : bodyFit.height
    drawLines(ctx, bodyFit.lines, innerX, y, { size: bodyFit.size, weight: 400, lh: bodyFit.lh, color: T.soft })
    y += textH
    if (bodyFit.clipped) {
      ctx.font = `700 ${bodyFit.size}px ${STACK}`
      ctx.fillStyle = accentText
      ctx.textBaseline = "alphabetic"
      ctx.textAlign = "left"
      const lastLine = bodyFit.lines[bodyFit.lines.length - 1]
      const endsWithDots = lastLine && lastLine.pieces[lastLine.pieces.length - 1]?.text === "…"
      ctx.fillText(`${endsWithDots ? "" : "… "}${readMore} →`, innerX, y + bodyFit.lh * 0.5 + bodyFit.size * 0.36)
      y += bodyFit.lh
    }
  }

  if (imgH) {
    y += gap
    coverImage(ctx, postImage, innerX, y, innerW, imgH, Math.round(S.radius * 0.6))
    ctx.strokeStyle = T.line
    ctx.lineWidth = 2
    roundRect(ctx, innerX, y, innerW, imgH, Math.round(S.radius * 0.6))
    ctx.stroke()
    y += imgH
  }

  // Engagement: real counts.
  const metaY = cardY + cardH - S.pad - footerH - metaH
  const c = data.counts
  const counts = reply ? [["heart", reply.likes], ["comment", reply.replies]] : (c ? [["heart", c.likes], ["comment", c.comments], ["repost", c.reshares]] : [])
  if (!reply && c?.seeds > 0) counts.push(["seed", c.seeds])
  let mx = innerX
  ctx.textBaseline = "middle"
  ctx.textAlign = "left"
  for (const [icon, n] of counts) {
    drawIcon(ctx, icon, mx, metaY + (metaH - S.icon) / 2, S.icon, T.muted, { width: 2 })
    mx += S.icon + 10
    ctx.font = `600 ${S.meta}px ${STACK}`
    ctx.fillStyle = T.muted
    const txt = icon === "seed" ? `${formatCount(n)} seeds` : formatCount(n)
    ctx.fillText(txt, mx, metaY + metaH / 2 + 1)
    mx += ctx.measureText(txt).width + S.meta * 1.3
  }

  // Footer: the mark, the short link and the QR code.
  if (!story) {
    const fy = cardY + cardH - S.pad - S.qr
    ctx.strokeStyle = T.line
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.moveTo(innerX, fy - Math.round(S.pad * 0.3))
    ctx.lineTo(innerX + innerW, fy - Math.round(S.pad * 0.3))
    ctx.stroke()
    if (data.qr) drawQR(ctx, data.qr, innerX + innerW - S.qr, fy + 6, S.qr - 6, "#0f1a16")
    const lh = Math.round(S.qr * 0.36)
    const lw = drawLogo(ctx, innerX, fy + S.qr / 2 - lh / 2 - S.meta * 0.9, lh, accentText)
    ctx.font = `700 ${Math.round(S.name * 0.95)}px ${STACK}`
    ctx.fillStyle = T.ink
    ctx.textBaseline = "middle"
    ctx.fillText("Brethreign", innerX + lw + 14, fy + S.qr / 2 - S.meta * 0.9)
    ctx.font = `600 ${S.meta}px ${STACK}`
    ctx.fillStyle = accentText
    ctx.fillText(data.link_label, innerX, fy + S.qr / 2 + S.meta * 0.95)
    ctx.font = `400 ${Math.round(S.meta * 0.88)}px ${STACK}`
    ctx.fillStyle = T.muted
    ctx.fillText(data.qr ? "Scan to join the conversation" : "Join the conversation", innerX, fy + S.qr / 2 + S.meta * 2.25)
  } else {
    const qy = H - 360
    const qs = S.qr
    const qx = S.margin + 8
    if (data.qr) drawQR(ctx, data.qr, qx, qy, qs, "#0f1a16")
    const tx = data.qr ? qx + qs + 44 : qx
    ctx.textAlign = "left"
    ctx.textBaseline = "alphabetic"
    ctx.fillStyle = T.ink
    ctx.font = `700 46px ${STACK}`
    ctx.fillText("Join the conversation", tx, qy + 70)
    ctx.fillStyle = accentText
    ctx.font = `600 34px ${STACK}`
    let link = data.link_label
    while (ctx.measureText(link).width > W - tx - S.margin && link.length > 6) link = link.slice(0, -2) + "…"
    ctx.fillText(link, tx, qy + 128)
    ctx.fillStyle = T.muted
    ctx.font = `400 30px ${STACK}`
    ctx.fillText("Scan or tap the link to read more", tx, qy + 180)
  }

  return canvas
}

export function canvasToBlob(canvas) {
  return new Promise((resolve, reject) => canvas.toBlob(b => (b ? resolve(b) : reject(new Error("Could not make the image"))), "image/png"))
}
