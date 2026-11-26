import { Controller } from "@hotwired/stimulus"

// "Share what I read": opens the sheet (its form loads the first time),
// shows the chosen key verse, and draws the reading as a status image
// (share/card_renderer.js, the same sheet as "Snapshot for status") from
// what's in the form right now, before or instead of posting it.
let sheetModule
const loadShareSheet = () => (sheetModule ||= import("../share/share_sheet").catch((error) => { sheetModule = null; throw error }))

export default class extends Controller {
  static targets = ["dialog", "frame", "form", "note", "verse", "versePreview", "burden", "notes"]

  open(event) {
    event?.preventDefault()
    const dialog = this.dialogTarget
    if (dialog.open) return
    if (typeof dialog.showModal === "function") dialog.showModal()
    else dialog.setAttribute("open", "")
    if (this.hasFrameTarget && this.frameTarget.getAttribute("loading") === "lazy") this.frameTarget.setAttribute("loading", "eager")
  }

  close(event) {
    event?.preventDefault()
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  pickVerse() {
    if (!this.hasVersePreviewTarget) return
    const option = this.verseTarget.selectedOptions[0]
    const text = option?.dataset.text || ""
    this.versePreviewTarget.textContent = text ? `“${text}”` : ""
    this.versePreviewTarget.hidden = !text
  }

  reading() {
    const form = this.formTarget.dataset
    const option = this.hasVerseTarget ? this.verseTarget.selectedOptions[0] : null
    const checked = (name) => this[`has${name}Target`] && this[`${name.toLowerCase()}Target`].checked
    return {
      id: `reading-${this.formTarget.querySelector("[name=chapter]").value}`,
      link: form.link,
      link_label: form.linkLabel,
      qr: null,
      accent: "#1f8a5b",
      accent_deep: "#14684a",
      share_text: `Read ${form.chapter} with me: read your Bible, pray every day. ${form.link}`,
      reading: {
        chapter: form.chapter,
        verse_label: option?.dataset.text ? option.dataset.label : null,
        verse_text: option?.dataset.text || null,
        translation: option?.dataset.text ? "KJV" : null,
        note: this.hasNoteTarget ? this.noteTarget.value.trim() || null : null,
        notes: checked("Notes") ? this.notesTarget.dataset.text : null,
        burden: checked("Burden") ? this.burdenTarget.dataset.text : null,
        streak: Number(form.streak) || 0,
        name: form.name || null
      }
    }
  }

  async image(event) {
    event?.preventDefault()
    if (!this.hasFormTarget) return
    try {
      const { openShareSheet } = await loadShareSheet()
      openShareSheet({ data: this.reading(), mode: "image" })
    } catch (error) {
      console.error("Status image failed to open", error)
    }
  }
}
