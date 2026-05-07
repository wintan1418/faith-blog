import { Controller } from "@hotwired/stimulus"

// Two responsibilities for the DM composer:
//   1. Show inline previews for any images the user attached.
//   2. Record a voice note via MediaRecorder, attach the resulting blob
//      to the form via a DataTransfer-backed FileList so submitting the
//      form ships it like any other file upload.
export default class extends Controller {
  static targets = ["previews", "imageInput", "recordBtn", "voicePreview", "voiceLength", "voiceField"]

  // ---- Image previews -----------------------------------------------------

  previewImages() {
    if (!this.hasPreviewsTarget || !this.hasImageInputTarget) return
    const files = Array.from(this.imageInputTarget.files || [])
    if (!files.length) {
      this.previewsTarget.classList.add("hidden")
      this.previewsTarget.innerHTML = ""
      return
    }

    this.previewsTarget.classList.remove("hidden")
    this.previewsTarget.innerHTML = files
      .slice(0, 4)
      .map(f => `<div class="dm-preview"><img src="${URL.createObjectURL(f)}" alt=""></div>`)
      .join("")
  }

  // ---- Voice notes --------------------------------------------------------

  async toggleRecord(event) {
    event.preventDefault()
    if (this.recording) {
      this.stopRecording()
    } else {
      await this.startRecording()
    }
  }

  async startRecording() {
    if (!navigator.mediaDevices || !window.MediaRecorder) {
      alert("Voice notes aren't supported in this browser.")
      return
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch (e) {
      alert("Microphone access denied.")
      return
    }

    this.chunks = []
    this.recording = true
    this.recordStart = Date.now()

    const mimeType = MediaRecorder.isTypeSupported("audio/webm;codecs=opus") ? "audio/webm;codecs=opus" : "audio/webm"
    this.recorder = new MediaRecorder(this.stream, { mimeType })

    this.recorder.ondataavailable = (e) => { if (e.data && e.data.size) this.chunks.push(e.data) }
    this.recorder.onstop = () => this.finalizeRecording(mimeType)
    this.recorder.start()

    this.recordBtnTarget.classList.add("is-recording")
    this.recordBtnTarget.textContent = "⏺"
    this.recordBtnTarget.title = "Stop recording"

    // Auto-stop at 2 minutes so a forgotten recorder can't run forever.
    this.autoStop = setTimeout(() => this.stopRecording(), 120_000)
  }

  stopRecording() {
    if (!this.recorder || this.recorder.state === "inactive") return
    this.recorder.stop()
    this.recording = false
    if (this.autoStop) { clearTimeout(this.autoStop); this.autoStop = null }
    this.recordBtnTarget.classList.remove("is-recording")
    this.recordBtnTarget.textContent = "🎙️"
    this.recordBtnTarget.title = "Record voice note"
  }

  finalizeRecording(mimeType) {
    if (this.stream) {
      this.stream.getTracks().forEach(t => t.stop())
      this.stream = null
    }
    if (!this.chunks.length) return

    const blob  = new Blob(this.chunks, { type: mimeType })
    const ext   = mimeType.includes("webm") ? "webm" : "ogg"
    const file  = new File([blob], `voice-${Date.now()}.${ext}`, { type: mimeType })
    const seconds = Math.max(1, Math.round((Date.now() - this.recordStart) / 1000))

    if (this.hasVoiceFieldTarget) {
      // The hidden field is a real <input type="hidden"> — replace it with
      // a transient <input type="file"> carrying our blob so Rails picks
      // it up as voice_note on submit.
      const fileInput = document.createElement("input")
      fileInput.type = "file"
      fileInput.name = this.voiceFieldTarget.name
      fileInput.style.display = "none"
      const dt = new DataTransfer()
      dt.items.add(file)
      fileInput.files = dt.files
      this.voiceFieldTarget.replaceWith(fileInput)
      fileInput.setAttribute("data-dm-composer-target", "voiceField")
    }

    if (this.hasVoicePreviewTarget) {
      this.voicePreviewTarget.classList.remove("hidden")
      if (this.hasVoiceLengthTarget) this.voiceLengthTarget.textContent = `${seconds}s`
    }
  }

  clearVoice(event) {
    event.preventDefault()
    if (this.hasVoicePreviewTarget) this.voicePreviewTarget.classList.add("hidden")
    if (this.hasVoiceFieldTarget) {
      const hidden = document.createElement("input")
      hidden.type  = "hidden"
      hidden.name  = this.voiceFieldTarget.name
      hidden.value = ""
      this.voiceFieldTarget.replaceWith(hidden)
      hidden.setAttribute("data-dm-composer-target", "voiceField")
    }
  }
}
