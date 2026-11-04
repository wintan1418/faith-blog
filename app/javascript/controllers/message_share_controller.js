import { Controller } from "@hotwired/stimulus"

// "Share" on a chat message: send its words, photo or document to another app
// (WhatsApp, email…) through the phone's share sheet. Falls back to copying
// the text where no share sheet exists.
export default class extends Controller {
  static values = { text: String, images: Array, files: Array }

  async share(event) {
    event.preventDefault()
    event.stopPropagation()
    this.element.closest(".msg-actions")?.classList.remove("is-open")
    const text = this.textValue
    const native = window.BrethreignNative // Android app 1.0.7+

    try {
      if (this.imagesValue.length) {
        const blob = await this.download(this.imagesValue[0])
        if (native?.shareImage) return native.shareImage(await this.pngDataUrl(blob), text)
        if (await this.shareFiles([ new File([ blob ], "photo.jpg", { type: blob.type || "image/jpeg" }) ], text)) return
      }

      if (this.filesValue.length && navigator.canShare) {
        const files = await Promise.all(this.filesValue.map(async f => new File([ await this.download(f.url) ], f.name, { type: f.type })))
        if (await this.shareFiles(files, text)) return
      }
    } catch (error) {
      if (error?.name === "AbortError") return // they closed the share sheet
      console.warn("[message-share] file share failed", error)
    }

    const words = text || this.filesValue.map(f => new URL(f.url, location.origin).href).join("\n")
    if (!words) return this.toast("This message can't be shared outside Brethreign.")
    if (native?.share) return native.share(words, "From Brethreign")
    if (navigator.share) {
      try { return await navigator.share({ text: words }) } catch (error) { if (error?.name === "AbortError") return }
    }
    this.copy(words)
  }

  async shareFiles(files, text) {
    if (!navigator.canShare?.({ files })) return false
    await navigator.share({ files, text: text || undefined })
    return true
  }

  async download(url) {
    const response = await fetch(url, { credentials: "same-origin" })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    return response.blob()
  }

  // The app's share bridge takes a PNG.
  async pngDataUrl(blob) {
    const bitmap = await createImageBitmap(blob)
    const canvas = Object.assign(document.createElement("canvas"), { width: bitmap.width, height: bitmap.height })
    canvas.getContext("2d").drawImage(bitmap, 0, 0)
    return canvas.toDataURL("image/png")
  }

  async copy(words) {
    try {
      if (window.BrethreignNative?.copy) window.BrethreignNative.copy(words)
      else await navigator.clipboard.writeText(words)
      this.toast("Copied. Paste it wherever you like.")
    } catch {
      this.toast("Couldn't share this message.", true)
    }
  }

  toast(message, error = false) {
    const holder = document.getElementById("flash_messages")
    if (!holder) return
    holder.innerHTML = `<div class="fc-toast-stack" data-controller="flash">
      <div class="fc-toast ${error ? "is-error" : "is-success"}" role="status" data-flash-target="message">
        <span class="fc-toast-dot" aria-hidden="true"></span><span class="fc-toast-text"></span>
        <button type="button" class="fc-toast-close" data-action="click->flash#dismiss" aria-label="Dismiss">×</button>
      </div></div>`
    holder.querySelector(".fc-toast-text").textContent = message
  }
}
