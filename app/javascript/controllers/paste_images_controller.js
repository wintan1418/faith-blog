import { Controller } from "@hotwired/stimulus"

// Paste a copied image straight into a composer (chat or breath). The image
// joins the form's photo picker, and the picker's own change handler shows
// the preview, so pasting works exactly like choosing a photo.
// Listens in the capture phase so it runs before the text editor sees it.
export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.onPaste = this.paste.bind(this)
    this.element.addEventListener("paste", this.onPaste, true)
  }

  disconnect() {
    this.element.removeEventListener("paste", this.onPaste, true)
  }

  paste(event) {
    if (!this.hasInputTarget) return
    const images = Array.from(event.clipboardData?.files || []).filter(file => file.type.startsWith("image/"))
    if (!images.length) return // plain text pastes as usual

    event.preventDefault()
    event.stopPropagation()

    const stamp = Date.now()
    const named = images.map((file, i) => {
      const ext = (file.type.split("/")[1] || "png").replace("jpeg", "jpg")
      const generic = !file.name || /^image\.\w+$/i.test(file.name)
      return new File([ file ], generic ? `pasted-${stamp}-${i + 1}.${ext}` : file.name, { type: file.type, lastModified: stamp + i })
    })

    const files = new DataTransfer()
    Array.from(this.inputTarget.files || []).forEach(file => files.items.add(file))
    named.forEach(file => files.items.add(file))
    this.inputTarget.files = files.files
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
