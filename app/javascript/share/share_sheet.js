// The sheet behind "Snapshot for status" and "Share as thread": a live
// preview of the image(s), Story / Square / Portrait, light or dark, and the
// ways out: the phone's share sheet (the app's native bridge, or
// navigator.share with files), or a download (one PNG, or a ZIP of a thread).
// A thread can also go out as one short video (share/thread_video.js).
import { FORMATS, renderCard, loadAssets, canvasToBlob, plainText } from "./card_renderer"
import { makeZip } from "./zip"

const MAX_REPLIES = 4
const STORE_KEY = "br-share-card"
// The video maker (and its MP4 muxer) loads only when a thread sheet opens.
let videoModule
const loadVideo = () => (videoModule ||= import("./thread_video").catch((error) => { videoModule = null; throw error }))
// Bytes per bridge call when handing a video to the app (a multiple of 3, so
// every piece is whole base64).
const BRIDGE_CHUNK = 3 * 256 * 1024

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
    this.savedKind = saved.kind
    this.kind = "cards"
    this.video = null
  }

  get thread() { return this.mode === "thread" }
  get videoMode() { return this.thread && this.kind === "video" }
  get nativeVideo() { return !!this.native?.shareVideo }

  open() {
    this.build()
    document.body.append(this.dialog)
    if (this.dialog.showModal) this.dialog.showModal()
    else this.dialog.setAttribute("open", "")
    this.load()
  }

  close() {
    this.stopVideo()
    this.dialog?.close?.()
    this.dialog?.remove()
  }

  stopVideo() {
    clearTimeout(this.videoTimer)
    this.videoAbort?.abort()
    if (this.video?.url) URL.revokeObjectURL(this.video.url)
    this.video = null
  }

  remember() { remember({ format: this.format, theme: this.theme, kind: this.thread ? this.kind : this.savedKind }) }

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

    // Thread: one video for status, or separate cards.
    this.kindButtons = [["video", "Video"], ["cards", "Cards"]].map(([key, text]) =>
      el("button", { type: "button", class: "share-chip", role: "radio", "data-kind": key, "aria-checked": "false", onclick: () => this.setKind(key) }, text))
    this.kindRow = el("div", { class: "share-row", hidden: true }, [
      el("span", { class: "share-row-label", text: "Share as" }),
      el("div", { class: "share-chips", role: "radiogroup", "aria-label": "Share as" }, this.kindButtons)
    ])
    this.videoNote = el("p", { class: "share-video-note", hidden: true })
    this.formatGroup = el("div", { class: "share-seg", role: "radiogroup", "aria-label": "Image size" }, this.formatButtons)

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
        this.kindRow,
        this.formatGroup,
        this.videoNote,
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
      if (this.thread) await this.setUpVideo()
      this.buildReplyPicker()
      this.render()
      this.updateActions()
    } catch (error) {
      this.stage.replaceChildren(el("p", { class: "share-sheet-error", text: error.message || "Something went wrong" }))
    }
  }

  // Video when this browser can make one and it can leave the page (in the
  // app, only through its shareVideo bridge); cards otherwise.
  async setUpVideo() {
    try {
      const { videoSupport } = await loadVideo()
      this.support = await videoSupport()
    } catch { this.support = null }
    if (!this.support) return
    this.kindRow.hidden = false
    const usable = !this.inApp || this.nativeVideo
    const saved = this.savedKind === "cards" || this.savedKind === "video" ? this.savedKind : null
    this.setKind(saved && (usable || saved === "cards") ? saved : (usable ? "video" : "cards"), { quiet: true })
  }

  setKind(kind, { quiet = false } = {}) {
    if (kind === "video" && !this.support) kind = "cards"
    if (kind === "cards") this.stopVideo()
    this.kind = kind
    this.kindButtons.forEach(b => b.setAttribute("aria-checked", String(b.dataset.kind === kind)))
    this.formatGroup.hidden = this.videoMode
    this.videoNote.hidden = !this.videoMode
    if (this.videoMode) {
      this.videoNote.textContent = this.support?.ext === "webm"
        ? "Story size, up to 20 seconds. This browser can only make WebM video, which WhatsApp status won't take: Chrome or Safari make MP4."
        : "Story size (1080×1920), up to 20 seconds: fits in one WhatsApp or Instagram status."
    }
    this.downloadButton.textContent = this.videoMode ? "Download video" : "Download all"
    this.setStatus("")
    if (!quiet) this.remember()
    if (this.data) this.render()
  }

  setFormat(format) {
    this.format = format
    this.formatButtons.forEach(b => b.setAttribute("aria-checked", String(b.dataset.format === format)))
    this.remember()
    this.render()
  }

  setTheme(theme) {
    this.theme = theme
    this.themeButtons.forEach(b => b.setAttribute("aria-checked", String(b.dataset.themeChoice === theme)))
    this.remember()
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
    if (this.videoMode) return this.renderVideo()
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

  // Makes the video (again) a moment after the last change, stopping any
  // video still being made for the old settings.
  renderVideo() {
    cancelAnimationFrame(this.frame)
    this.stopVideo()
    this.canvases = []
    const bar = el("span", { class: "share-video-bar-fill" })
    const label = el("span", { class: "share-video-label", text: "Making your video…" })
    this.stage.classList.remove("is-strip")
    this.stage.dataset.previewFormat = "video"
    this.stage.dataset.previewTheme = this.theme
    this.stage.replaceChildren(el("div", { class: "share-video-progress", "data-testid": "share-video-progress" }, [
      label, el("span", { class: "share-video-bar", "aria-hidden": "true" }, bar)
    ]))
    this.updateActions()
    const controller = new AbortController()
    this.videoAbort = controller
    this.videoTimer = setTimeout(async () => {
      try {
        const { makeThreadVideo } = await loadVideo()
        let shown = -1
        const result = await makeThreadVideo(this.data, {
          theme: this.theme, assets: this.assets, replies: this.replies(), signal: controller.signal,
          onProgress: (p) => {
            const pct = Math.floor(p * 100)
            if (pct === shown) return
            shown = pct
            bar.style.width = `${pct}%`
            label.textContent = `Making your video… ${pct}%`
          }
        })
        if (controller.signal.aborted) return
        const url = URL.createObjectURL(result.blob)
        this.video = { ...result, url, file: new File([result.blob], `brethreign-thread-${this.data.id}.${result.ext}`, { type: result.type }) }
        const player = el("video", { class: "share-sheet-video", "data-testid": "share-video", src: url, muted: true, loop: true, playsinline: true, autoplay: true, controls: true, "aria-label": "Your thread as a video" })
        player.muted = true
        this.stage.replaceChildren(el("figure", { class: "share-slide" }, [player,
          el("figcaption", {}, [el("span", { text: `${Math.round(result.duration)}s · ${result.ext.toUpperCase()} · ${(result.blob.size / 1048576).toFixed(1)} MB` })])]))
        player.play?.()?.catch?.(() => {})
        this.updateActions()
      } catch (error) {
        if (error?.name === "AbortError" || controller.signal.aborted) return
        console.error("Thread video failed", error)
        this.stage.replaceChildren(el("p", { class: "share-sheet-error", text: "Couldn't make the video on this device. Try Cards instead." }))
      }
    }, 250)
  }

  canShareFiles(files) {
    if (!navigator.share || !navigator.canShare) return false
    try {
      const probe = files || [new File([new Blob(["x"], { type: "image/png" })], "probe.png", { type: "image/png" })]
      return navigator.canShare({ files: probe })
    } catch { return false }
  }

  updateActions() {
    if (this.videoMode) return this.updateVideoActions()
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

  updateVideoActions() {
    const ready = !!this.video
    const probe = ready ? this.video.file : new File([new Blob(["x"], { type: "video/mp4" })], "probe.mp4", { type: "video/mp4" })
    const webShare = this.canShareFiles([probe])
    this.shareButton.textContent = "Share video"
    this.shareButton.hidden = !(this.nativeVideo || webShare || this.inApp)
    this.shareButton.disabled = !ready || (this.inApp && !this.nativeVideo)
    this.downloadButton.hidden = this.inApp
    this.downloadButton.disabled = !ready
    if (this.inApp && !this.nativeVideo) this.setStatus("Update the Brethreign app to share videos. Cards still work.")
    else if (ready && this.video.ext === "webm") this.setStatus("WebM video: fine for X and LinkedIn, but WhatsApp status needs MP4.")
    else this.setStatus("")
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
    if (this.videoMode) return this.shareVideo()
    const text = this.data.share_text
    try {
      if (this.native?.shareImage) {
        if (this.canvases.length > 1 && this.native.shareImages) {
          // A JSON list: the Android bridge only takes strings.
          this.native.shareImages(JSON.stringify(this.canvases.map(c => c.toDataURL("image/png"))), text)
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

  async shareVideo() {
    const video = this.video
    if (!video) return
    const text = this.data.share_text
    try {
      if (this.nativeVideo) {
        this.setStatus("Opening the share sheet…")
        await this.sendVideoToApp(video)
        this.setStatus("")
        return
      }
      if (this.canShareFiles([video.file])) {
        await navigator.share({ files: [video.file], text, title: plainText(this.data.title || "A thread on Brethreign") })
        this.setStatus("Shared")
        return
      }
      this.save(video.file, video.file.name)
      this.setStatus("Saved to your downloads")
    } catch (error) {
      if (error?.name === "AbortError") return
      this.setStatus("Couldn't open the share sheet. Try Download instead.")
    }
  }

  // The app's bridge takes strings: in pieces when it can (shareVideoChunk),
  // or as one base64 string.
  async sendVideoToApp(video) {
    const text = this.data.share_text
    const asBase64 = (blob) => new Promise((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = () => resolve(String(reader.result).split("base64,").pop())
      reader.onerror = () => reject(reader.error)
      reader.readAsDataURL(blob)
    })
    if (this.native.shareVideoChunk) {
      const { blob } = video
      for (let i = 0, at = 0; at < blob.size; i++, at += BRIDGE_CHUNK) {
        this.native.shareVideoChunk(i, await asBase64(blob.slice(at, at + BRIDGE_CHUNK)))
      }
      this.native.shareVideo("", video.type, text)
    } else {
      this.native.shareVideo(await asBase64(video.blob), video.type, text)
    }
  }

  async downloadAll() {
    if (this.videoMode) {
      if (!this.video) return
      this.save(this.video.file, this.video.file.name)
      this.setStatus("Saved to your downloads")
      return
    }
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
