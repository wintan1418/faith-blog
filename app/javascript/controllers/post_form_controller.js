import { Controller } from "@hotwired/stimulus"

const MAX_FILES = 5

export default class extends Controller {
  static targets = ["previews"]

  connect() {
    this.accumulator = []
  }

  previewImages(event) {
    const input = event.target
    const newFiles = Array.from(input.files || [])
    if (!this.accumulator) this.accumulator = []

    // Accumulate across picks instead of replacing — the native <input type="file">
    // overwrites its FileList on each pick, so picking image A then image B
    // would otherwise drop A. Dedupe by name+size+lastModified.
    const seen = new Set(this.accumulator.map(f => `${f.name}|${f.size}|${f.lastModified}`))
    for (const f of newFiles) {
      const key = `${f.name}|${f.size}|${f.lastModified}`
      if (seen.has(key)) continue
      this.accumulator.push(f)
      seen.add(key)
    }

    if (this.accumulator.length > MAX_FILES) {
      alert(`You can only upload up to ${MAX_FILES} images. Only the first ${MAX_FILES} will be used.`)
      this.accumulator = this.accumulator.slice(0, MAX_FILES)
    }

    this.syncInputFiles(input)
    this.renderPreviews(input)
  }

  syncInputFiles(input) {
    const dt = new DataTransfer()
    this.accumulator.forEach(f => dt.items.add(f))
    input.files = dt.files
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
          this.accumulator.splice(index, 1)
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
