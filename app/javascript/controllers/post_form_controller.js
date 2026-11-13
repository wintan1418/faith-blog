import { Controller } from "@hotwired/stimulus"
import { prepareImage } from "../helpers/prepare_image"

const MAX_FILES = 5

export default class extends Controller {
  static targets = ["previews"]

  connect() {
    this.accumulator = []
    this.pickedKeys = new Set()
  }

  async previewImages(event) {
    const input = event.target
    const newFiles = Array.from(input.files || [])
    if (!this.accumulator) this.accumulator = []
    if (!this.pickedKeys) this.pickedKeys = new Set()
    // The change event fires again when we put the prepared files back.
    if (this.syncing) return

    // Accumulate across picks instead of replacing — the native <input type="file">
    // overwrites its FileList on each pick, so picking image A then image B
    // would otherwise drop A. Dedupe by name+size+lastModified of what was picked.
    const fresh = newFiles.filter(f => !this.accumulator.includes(f) && !this.pickedKeys.has(this.keyFor(f)))
    if (!fresh.length) { if (!this.pending) this.syncInputFiles(input); return }
    // Claim them now, so a second change event during the copy can't add them twice.
    fresh.forEach(f => this.pickedKeys.add(this.keyFor(f)))

    this.pending = (this.pending || 0) + 1
    this.setPreparing(input, true)
    const failed = []
    for (const f of fresh) {
      try {
        const ready = await prepareImage(f)
        ready.pickedFrom = this.keyFor(f)
        this.pickedKeys.add(this.keyFor(ready))
        this.accumulator.push(ready)
      } catch {
        this.pickedKeys.delete(this.keyFor(f))
        failed.push(f.name || "a photo")
      }
    }
    this.pending -= 1
    if (!this.pending) this.setPreparing(input, false)

    if (failed.length) {
      alert(`Couldn't open ${failed.join(", ")}. Please choose the photo again.`)
    }
    if (this.accumulator.length > MAX_FILES) {
      alert(`You can only upload up to ${MAX_FILES} images. Only the first ${MAX_FILES} will be used.`)
      this.accumulator = this.accumulator.slice(0, MAX_FILES)
    }

    this.syncInputFiles(input)
    this.renderPreviews(input)
  }

  keyFor(file) {
    return `${file.name}|${file.size}|${file.lastModified}`
  }

  // While photos are being copied the post can't be sent yet: the button says so.
  setPreparing(input, on) {
    const form = input.closest("form")
    if (!form) return
    form.querySelectorAll("[type=submit]").forEach(button => {
      if (on) {
        button.dataset.preparingWas = button.disabled ? "1" : "0"
        button.disabled = true
        button.setAttribute("aria-busy", "true")
      } else {
        button.disabled = button.dataset.preparingWas === "1"
        button.removeAttribute("aria-busy")
        delete button.dataset.preparingWas
      }
    })
    form.classList.toggle("is-preparing-photos", on)
  }

  syncInputFiles(input) {
    const dt = new DataTransfer()
    this.accumulator.forEach(f => dt.items.add(f))
    this.syncing = true
    input.files = dt.files
    this.syncing = false
  }

  renderPreviews(input) {
    if (!this.hasPreviewsTarget) return
    const container = this.previewsTarget
    container.innerHTML = ""

    if (this.accumulator.length === 0) {
      container.classList.add("hidden")
      return
    }
    container.classList.remove("hidden")

    this.accumulator.forEach((file, index) => {
      if (!file.type.startsWith("image/")) return
      const reader = new FileReader()
      reader.onload = (e) => {
        const div = document.createElement("div")
        div.className = "relative group"

        const img = document.createElement("img")
        img.src = e.target.result
        img.className = "w-full h-24 object-cover rounded-lg"

        const removeBtn = document.createElement("button")
        removeBtn.type = "button"
        removeBtn.className = "absolute top-1 right-1 w-6 h-6 bg-red-500 text-white rounded-full opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center text-xs"
        removeBtn.innerHTML = "×"
        removeBtn.onclick = () => {
          const [ removed ] = this.accumulator.splice(index, 1)
          if (removed) {
            this.pickedKeys.delete(this.keyFor(removed))
            if (removed.pickedFrom) this.pickedKeys.delete(removed.pickedFrom)
          }
          this.syncInputFiles(input)
          this.renderPreviews(input)
        }

        div.appendChild(img)
        div.appendChild(removeBtn)
        container.appendChild(div)
      }
      reader.readAsDataURL(file)
    })
  }
}
