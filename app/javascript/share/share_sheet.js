// The sheet behind "Snapshot for status" and "Share as thread": a live
// preview of the image(s), Story / Square / Portrait, light or dark, and the
// ways out: the phone's share sheet (the app's native bridge, or
// navigator.share with files), or a download (one PNG, or a ZIP of a thread).
import { FORMATS, renderCard, loadAssets, canvasToBlob, plainText } from "./card_renderer"
import { makeZip } from "./zip"

const MAX_REPLIES = 4
const STORE_KEY = "br-share-card"

const remember = (value) => { try { localStorage.setItem(STORE_KEY, JSON.stringify(value)) } catch { /* private mode */ } }
const recall = () => { try { return JSON.parse(localStorage.getItem(STORE_KEY) || "{}") || {} } catch { return {} } }

function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag)
  for (const [key, value] of Object.entries(attrs)) {
    if (value === false || value == null) continue
    if (key === "class") node.className = value
    else if (key === "text") node.textContent = value
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value)
    else node.setAttribute(key, value === true ? "" : value)
  }
  for (const child of [].concat(children)) if (child) node.append(child)
  return node
}

export function openShareSheet(options) {
  const sheet = new ShareSheet(options)
  sheet.open()
  return sheet
}

class ShareSheet {
  constructor({ cardUrl, data, mode = "image", flash }) {
    this.cardUrl = cardUrl
    this.preset = data
    this.mode = mode
    this.flash = flash || (() => {})
    const saved = recall()
    const siteDark = document.documentElement.dataset.theme === "dark"
    this.format = FORMATS[saved.format] ? saved.format : "story"
    this.theme = saved.theme === "dark" || saved.theme === "light" ? saved.theme : (siteDark ? "dark" : "light")
    this.native = window.BrethreignNative
    this.inApp = /Hotwire Native|Turbo Native/.test(navigator.userAgent)
    this.canvases = []
    this.selected = []
  }

  get thread() { return this.mode === "thread" }

  open() {
    this.build()
    document.body.append(this.dialog)
    if (this.dialog.showModal) this.dialog.showModal()
    else this.dialog.setAttribute("open", "")
    this.load()
  }

  close() {
    this.dialog?.close?.()
    this.dialog?.remove()
  }

  build() {
    this.status = el("p", { class: "share-sheet-status", role: "status", "aria-live": "polite" })
    this.stage = el("div", { class: "share-sheet-stage", "data-testid": "share-stage" }, [
      el("div", { class: "share-sheet-loading" }, [el("span", { class: "share-sheet-spinner", "aria-hidden": "true" }), el("span", { text: this.thread ? "Drawing your thread…" : "Drawing your breath…" })])
    ])

    this.formatButtons = Object.entries(FORMATS).map(([key, f]) =>
      el("button", { type: "button", class: "share-seg-btn", role: "radio", "data-format": key, "aria-checked": String(key === this.format), onclick: () => this.setFormat(key) }, [
        el("span", { class: "share-seg-shape", "data-shape": key, "aria-hidden": "true" }),
        el("span", { class: "share-seg-text" }, [el("strong", { text: f.label }), el("small", { text: f.hint })])
      ]))
    this.themeButtons = ["light", "dark"].map(key =>
      el("button", { type: "button", class: "share-chip", role: "radio", "data-theme-choice": key, "aria-checked": String(key === this.theme), onclick: () => this.setTheme(key) },
        [el("span", { class: `share-chip-dot is-${key}`, "aria-hidden": "true" }), key === "light" ? "Light" : "Dark"]))

    this.replyBox = el("div", { class: "share-replies", hidden: true })

    this.shareButton = el("button", { type: "button", class: "share-btn share-btn-primary", "data-testid": "share-go", disabled: true, onclick: () => this.shareAll() }, "Share")
    this.downloadButton = el("button", { type: "button", class: "share-btn", "data-testid": "share-download", disabled: true, onclick: () => this.downloadAll() }, this.thread ? "Download all" : "Download")

    const panel = el("div", { class: "share-sheet-panel" }, [
      el("header", { class: "share-sheet-head" }, [
        el("div", {}, [
          el("h2", { class: "share-sheet-title", text: this.thread ? "Share as thread" : "Share as image" }),
          el("p", { class: "share-sheet-sub", text: this.thread ? "Your breath and its best replies, one card each." : "A card for status, stories and feeds. The QR code and link bring people back to it." })
        ]),
        el("button", { type: "button", class: "share-sheet-close", "aria-label": "Close", onclick: () => this.close() }, "×")
      ]),
      this.stage,
      el("div", { class: "share-sheet-controls" }, [
        el("div", { class: "share-seg", role: "radiogroup", "aria-label": "Image size" }, this.formatButtons),
        el("div", { class: "share-row" }, [
          el("span", { class: "share-row-label", text: "Card" }),
          el("div", { class: "share-chips", role: "radiogroup", "aria-label": "Card theme" }, this.themeButtons)
        ]),
        this.replyBox
      ]),
      el("footer", { class: "share-sheet-foot" }, [this.status, el("div", { class: "share-sheet-actions" }, [this.downloadButton, this.shareButton])])
    ])

    this.dialog = el("dialog", { class: "share-sheet", "aria-label": this.thread ? "Share as thread" : "Share as image" }, panel)
    this.dialog.addEventListener("click", (e) => { if (e.target === this.dialog) this.close() })
    this.dialog.addEventListener("close", () => this.dialog.remove())
  }

  async getJSON(url) {
    const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
    const data = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(data.error || "Couldn't load this breath")
    return data
  }

  async load() {
    try {
      let data = this.preset
      if (!data) {
        const url = new URL(this.cardUrl, window.location.origin)
        if (this.thread) url.searchParams.set("thread", "1")
        data = await this.getJSON(url)
      }
      if (!data.qr && data.link) {
        const qrUrl = new URL("/share/qr", window.location.origin)
        qrUrl.searchParams.set("url", data.link)
        data.qr = (await this.getJSON(qrUrl).catch(() => ({}))).qr || null
      }
      this.data = data
      this.selected = (data.replies || []).map(r => r.id)
      this.assets = await loadAssets(data)
      this.buildReplyPicker()
      this.render()
      this.updateActions()
    } catch (error) {
      this.stage.replaceChildren(el("p", { class: "share-sheet-error", text: error.message || "Something went wrong" }))
    }
  }

  setFormat(format) {
    this.format = format
    this.formatButtons.forEach(b => b.setAttribute("aria-checked", String(b.dataset.format === format)))
    remember({ format: this.format, theme: this.theme })
    this.render()
  }

  setTheme(theme) {
    this.theme = theme
    this.themeButtons.forEach(b => b.setAttribute("aria-checked", String(b.dataset.themeChoice === theme)))
    remember({ format: this.format, theme: this.theme })
    this.render()
  }

  replies() {
    if (!this.thread || !this.data) return []
    const pool = this.data.reply_candidates || []
    return this.selected.map(id => pool.find(r => r.id === id)).filter(Boolean).slice(0, MAX_REPLIES)
  }

  buildReplyPicker() {
    if (!this.thread) return
    const pool = this.data.reply_candidates || []
    this.replyBox.hidden = false
    if (!pool.length) {
      this.replyBox.replaceChildren(el("p", { class: "share-replies-note", text: "No replies can go in yet, so this is just your breath." }))
      return
    }
    if (!this.data.can_choose_replies) {
      this.replyBox.replaceChildren(el("p", { class: "share-replies-note", text: "Includes the most-liked replies. Replies from people you've blocked are never included." }))
      return
    }
    const items = pool.map(reply => {
      const box = el("input", { type: "checkbox", value: reply.id, checked: this.selected.includes(reply.id) })
      box.addEventListener("change", () => {
        if (box.checked) this.selected.push(reply.id)
        else this.selected = this.selected.filter(id => id !== reply.id)
        this.syncPicker()
        this.render()
      })
      const who = reply.author.anonymous ? reply.author.name : `@${reply.author.username}`
      return el("label", { class: "share-reply" }, [box, el("span", { class: "share-reply-who", text: who }),
        el("span", { class: "share-reply-text", text: plainText(reply.text).slice(0, 90) }),
        el("span", { class: "share-reply-likes", text: `♥ ${reply.likes}` })])
    })
    this.replyBox.replaceChildren(el("p", { class: "share-row-label", text: `Replies to include (up to ${MAX_REPLIES})` }), el("div", { class: "share-reply-list" }, items))
    this.syncPicker()
  }

  syncPicker() {
    const full = this.selected.length >= MAX_REPLIES
    this.replyBox.querySelectorAll("input[type=checkbox]").forEach(box => { box.disabled = !box.checked && full })
  }

  render() {
    if (!this.data) return
    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => {
      const replies = this.replies()
      const total = this.thread ? replies.length + 1 : 1
      const base = { format: this.format, theme: this.theme, assets: this.assets, total }
      this.canvases = [renderCard(this.data, { ...base, index: 1 })]
      replies.forEach((reply, i) => this.canvases.push(renderCard(this.data, { ...base, reply, index: i + 2 })))
      this.stage.dataset.previewFormat = this.format
      this.stage.dataset.previewTheme = this.theme
      this.stage.classList.toggle("is-strip", this.canvases.length > 1)
      this.stage.replaceChildren(...this.canvases.map((canvas, i) => {
        canvas.className = "share-sheet-canvas"
        canvas.setAttribute("role", "img")
        canvas.setAttribute("aria-label", `Card ${i + 1} of ${this.canvases.length}`)
        const slide = el("figure", { class: "share-slide" }, canvas)
        if (this.canvases.length > 1) {
          slide.append(el("figcaption", {}, [
            el("span", { text: `${i + 1}/${this.canvases.length}` }),
            el("button", { type: "button", class: "share-slide-btn", onclick: () => this.shareOne(i) }, this.canShareFiles() || this.native ? "Share" : "Save")
          ]))
        }
        return slide
      }))
      this.updateActions()
    })
  }

  canShareFiles(files) {
    if (!navigator.share || !navigator.canShare) return false
    try {
      const probe = files || [new File([new Blob(["x"], { type: "image/png" })], "probe.png", { type: "image/png" })]
      return navigator.canShare({ files: probe })
    } catch { return false }
  }

  updateActions() {
    const ready = this.canvases.length > 0
    const nativeOk = !!this.native?.shareImage
    const shareable = nativeOk || this.canShareFiles()
    this.shareButton.hidden = !shareable
    this.shareButton.disabled = !ready
    this.downloadButton.hidden = this.inApp
    this.downloadButton.disabled = !ready
    if (this.inApp && !nativeOk) this.setStatus("Update the Brethreign app to share images.")
    if (this.thread && nativeOk && !this.native.shareImages && this.canvases.length > 1) {
      this.shareButton.textContent = "Share first card"
      this.setStatus("The app shares one card at a time: use Share under each card.")
    } else {
      this.shareButton.textContent = this.thread && this.canvases.length > 1 ? `Share ${this.canvases.length} images` : "Share"
    }
  }

  setStatus(text) { this.status.textContent = text || "" }

  fileName(i) {
    const id = this.data?.id || "breath"
    return this.canvases.length > 1 ? `brethreign-thread-${id}-${i + 1}of${this.canvases.length}.png` : `brethreign-${id}-${this.format}.png`
  }

  async files() {
    return Promise.all(this.canvases.map(async (canvas, i) => new File([await canvasToBlob(canvas)], this.fileName(i), { type: "image/png" })))
  }

  async shareAll() {
    const text = this.data.share_text
    try {
      if (this.native?.shareImage) {
        if (this.canvases.length > 1 && this.native.shareImages) {
          this.native.shareImages(this.canvases.map(c => c.toDataURL("image/png")), text)
        } else {
          this.native.shareImage(this.canvases[0].toDataURL("image/png"), text)
        }
        return
      }
      const files = await this.files()
      if (this.canShareFiles(files)) {
        await navigator.share({ files, text, title: plainText(this.data.title || "A breath on Brethreign") })
        this.setStatus("Shared")
        return
      }
      await this.downloadAll()
    } catch (error) {
      if (error?.name === "AbortError") return
      this.setStatus("Couldn't open the share sheet. Try Download instead.")
    }
  }

  async shareOne(i) {
    const canvas = this.canvases[i]
    if (!canvas) return
    try {
      if (this.native?.shareImage) return this.native.shareImage(canvas.toDataURL("image/png"), this.data.share_text)
      const file = new File([await canvasToBlob(canvas)], this.fileName(i), { type: "image/png" })
      if (this.canShareFiles([file])) return await navigator.share({ files: [file], text: this.data.share_text })
      this.save(file, file.name)
    } catch (error) {
      if (error?.name !== "AbortError") this.setStatus("Couldn't share that card.")
    }
  }

  async downloadAll() {
    const files = await this.files()
    if (files.length === 1) {
      this.save(files[0], files[0].name)
      this.setStatus("Saved to your downloads")
      return
    }
    const zip = await makeZip(files.map(f => ({ name: f.name, blob: f })))
    this.save(zip, `brethreign-thread-${this.data.id}.zip`)
    this.setStatus(`Saved ${files.length} images as a ZIP`)
  }

  save(blob, name) {
    const url = URL.createObjectURL(blob)
    const a = el("a", { href: url, download: name })
    document.body.append(a)
    a.click()
    a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 4000)
  }
}
