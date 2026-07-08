import { Controller } from "@hotwired/stimulus"

// Two responsibilities for the DM composer:
//   1. Show inline previews for any images the user attached.
//   2. Record a voice note via MediaRecorder, attach the resulting blob
//      to the form via a DataTransfer-backed FileList so submitting the
//      form ships it like any other file upload.
export default class extends Controller {
  static targets = ["previews", "imageInput", "recordBtn", "sendBtn", "voicePreview", "voiceLength", "voiceField", "bodyInput", "scriptureField", "scripturePreview", "scriptureLabel", "versePanel", "verseInput"]

  connect() {
    // Hide mic if browser can't record; force send-button visibility.
    if (this.hasRecordBtnTarget && !(navigator.mediaDevices && window.MediaRecorder)) {
      this.recordBtnTarget.classList.add("hidden")
      if (this.hasSendBtnTarget) this.sendBtnTarget.classList.remove("hidden")
    }
    this.syncTrailingAction()
  }

  onInput() {
    this.syncTrailingAction()
  }

  onKeydown(event) {
    // Cmd/Ctrl + Enter sends. Plain Enter inserts a newline.
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      this.element.requestSubmit()
    }
  }

  syncTrailingAction() {
    if (!this.hasRecordBtnTarget || !this.hasSendBtnTarget) return
    const hasText  = this.hasBodyInputTarget && this.bodyInputTarget.value.trim().length > 0
    const hasFiles = this.hasImageInputTarget && this.imageInputTarget.files && this.imageInputTarget.files.length > 0
    const hasVoice = this.hasVoicePreviewTarget && !this.voicePreviewTarget.classList.contains("hidden")
    const hasVerse = this.hasScriptureFieldTarget && this.scriptureFieldTarget.value.trim().length > 0
    const showSend = hasText || hasFiles || hasVoice || hasVerse

    this.recordBtnTarget.classList.toggle("hidden", showSend)
    this.sendBtnTarget.classList.toggle("hidden", !showSend)
  }

  // ---- Shared scripture ---------------------------------------------------

  toggleVersePanel(event) {
    event.preventDefault()
    if (!this.hasVersePanelTarget) return

    const opening = this.versePanelTarget.classList.contains("hidden")
    this.versePanelTarget.classList.toggle("hidden", !opening)
    if (opening && this.hasVerseInputTarget) {
      // Prefill with whatever verse is already attached, then focus.
      this.verseInputTarget.value = this.hasScriptureFieldTarget ? this.scriptureFieldTarget.value : ""
      this.verseInputTarget.focus()
    }
  }

  verseKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.attachVerse(event)
    } else if (event.key === "Escape") {
      this.versePanelTarget.classList.add("hidden")
    }
  }

  attachVerse(event) {
    if (event) event.preventDefault()
    if (!this.hasVerseInputTarget || !this.hasScriptureFieldTarget) return

    const ref = this.verseInputTarget.value.trim()
    if (!ref) {
      this.clearVerse()
      return
    }

    this.scriptureFieldTarget.value = ref
    if (this.hasScriptureLabelTarget) this.scriptureLabelTarget.textContent = ref
    if (this.hasScripturePreviewTarget) this.scripturePreviewTarget.classList.remove("hidden")
    if (this.hasVersePanelTarget) this.versePanelTarget.classList.add("hidden")
    this.syncTrailingAction()
  }

  clearVerse(event) {
    if (event) event.preventDefault()
    if (this.hasScriptureFieldTarget) this.scriptureFieldTarget.value = ""
    if (this.hasScripturePreviewTarget) this.scripturePreviewTarget.classList.add("hidden")
    if (this.hasVerseInputTarget) this.verseInputTarget.value = ""
    this.syncTrailingAction()
  }

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
    this.syncTrailingAction()
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
    this.syncTrailingAction()
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
    this.syncTrailingAction()
  }
}
