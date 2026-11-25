import { Controller } from "@hotwired/stimulus"

// Shows a picked logo or cover straight away, before the form is sent.
export default class extends Controller {
  static targets = ["logo", "cover"]

  show(event) {
    const input = event.target
    const file = input.files && input.files[0]
    const name = input.dataset.preview
    const box = name === "logo" ? (this.hasLogoTarget && this.logoTarget) : (this.hasCoverTarget && this.coverTarget)
    if (!box) return
    box.innerHTML = ""
    if (!file || !file.type.startsWith("image/")) return
    const img = document.createElement("img")
    img.alt = ""
    img.src = URL.createObjectURL(file)
    img.onload = () => URL.revokeObjectURL(img.src)
    box.appendChild(img)
  }
}
