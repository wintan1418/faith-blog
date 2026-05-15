import { Controller } from "@hotwired/stimulus"

// Record a voice note for a breath. Click the mic — the panel opens,
// requests microphone access, records up to MAX_MS, then offers playback
// / re-record / discard. On save we stash the Blob into the hidden
// post[voice_note] file input (via DataTransfer) and write the recorded
// duration in ms into post[voice_duration_ms] so the player can show
// the total time before the audio is even loaded.
const MAX_MS = 90_000

export default class extends Controller {
  static targets = [
    "trigger", "panel", "recordBtn", "stopBtn", "timer", "wave",
    "preview", "previewAudio", "discardBtn", "retryBtn",
    "fileInput", "durationInput", "summary", "summaryDuration", "removeBtn"
  ]

  connect() {
    this.chunks = []
    this.blob = null
    this.recorder = null
    this.startedAt = 0
    this.stopAt = null
    this.tickHandle = null
    this.stream = null
    this.objectUrl = null
  }

  disconnect() {
    this.releaseStream()
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
  }

  togglePanel(event) {
    event?.preventDefault()
    this.panelTarget.classList.toggle("hidden")
  }

  closePanel() {
    this.panelTarget.classList.add("hidden")
  }

  async record(event) {
    event?.preventDefault()
    this.resetRecorderUI()

    if (!navigator.mediaDevices?.getUserMedia) {
      this.flash("Your browser can't record audio.")
      return
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch {
      this.flash("Microphone permission denied.")
      return
    }

    const mime = this.pickMime()
    try {
      this.recorder = new MediaRecorder(this.stream, mime ? { mimeType: mime } : undefined)
    } catch {
      this.flash("Recording isn't supported on this device.")
      this.releaseStream()
      return
    }

    this.chunks = []
    this.recorder.ondataavailable = (e) => { if (e.data?.size) this.chunks.push(e.data) }
    this.recorder.onstop = () => this.onRecordingStop()
    this.recorder.start()
    this.startedAt = Date.now()
    this.stopAt = this.startedAt + MAX_MS

    this.panelTarget.classList.remove("hidden")
    this.element.classList.add("is-recording")
    this.recordBtnTarget.classList.add("hidden")
    this.stopBtnTarget.classList.remove("hidden")
    this.previewTarget.classList.add("hidden")

    this.tick()
  }

  stop(event) {
    event?.preventDefault()
    if (this.recorder && this.recorder.state !== "inactive") this.recorder.stop()
  }

  onRecordingStop() {
    cancelAnimationFrame(this.tickHandle)
    const type = (this.recorder?.mimeType || "audio/webm").split(";")[0]
    this.blob = new Blob(this.chunks, { type })
    this.durationMs = Math.min(Date.now() - this.startedAt, MAX_MS)
    this.releaseStream()

    this.element.classList.remove("is-recording")
    this.recordBtnTarget.classList.remove("hidden")
    this.stopBtnTarget.classList.add("hidden")
    this.timerTarget.textContent = this.fmt(this.durationMs)

    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = URL.createObjectURL(this.blob)
    this.previewAudioTarget.src = this.objectUrl
    this.previewTarget.classList.remove("hidden")

    this.attachToForm()
  }

  attachToForm() {
    if (!this.blob || !this.hasFileInputTarget) return
    const ext  = (this.blob.type.includes("mp4")  ? "m4a" :
                  this.blob.type.includes("mpeg") ? "mp3" :
                  this.blob.type.includes("ogg")  ? "ogg" : "webm")
    const file = new File([this.blob], `voice-${Date.now()}.${ext}`, { type: this.blob.type })

    try {
      const dt = new DataTransfer()
      dt.items.add(file)
      this.fileInputTarget.files = dt.files
    } catch {
      // Some browsers block programmatic file input assignment; fall back
      // to a hidden field with a base64 payload would be heavier — keep
      // it simple and let the form submission fail loudly if so.
      this.flash("This browser can't attach the recording to the form.")
      return
    }

    if (this.hasDurationInputTarget) {
      this.durationInputTarget.value = String(this.durationMs)
    }

    if (this.hasSummaryTarget) {
      this.summaryTarget.classList.remove("hidden")
      if (this.hasSummaryDurationTarget) {
        this.summaryDurationTarget.textContent = this.fmt(this.durationMs)
      }
    }
  }

  retry(event) {
    event?.preventDefault()
    this.resetRecorderUI()
  }

  discard(event) {
    event?.preventDefault()
    this.resetRecorderUI()
    this.detachFromForm()
    this.closePanel()
  }

  remove(event) {
    event?.preventDefault()
    this.detachFromForm()
    if (this.hasSummaryTarget) this.summaryTarget.classList.add("hidden")
  }

  detachFromForm() {
    this.blob = null
    if (this.objectUrl) { URL.revokeObjectURL(this.objectUrl); this.objectUrl = null }
    if (this.hasFileInputTarget) this.fileInputTarget.value = ""
    if (this.hasDurationInputTarget) this.durationInputTarget.value = ""
  }

  resetRecorderUI() {
    this.previewTarget.classList.add("hidden")
    this.timerTarget.textContent = "0:00"
    this.element.classList.remove("is-recording")
    this.recordBtnTarget.classList.remove("hidden")
    this.stopBtnTarget.classList.add("hidden")
  }

  tick() {
    const elapsed = Date.now() - this.startedAt
    if (elapsed >= MAX_MS) { this.stop(); return }
    this.timerTarget.textContent = this.fmt(elapsed)
    this.tickHandle = requestAnimationFrame(() => this.tick())
  }

  pickMime() {
    const candidates = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg"]
    for (const c of candidates) {
      if (window.MediaRecorder?.isTypeSupported?.(c)) return c
    }
    return ""
  }

  releaseStream() {
    if (this.stream) {
      this.stream.getTracks().forEach(t => t.stop())
      this.stream = null
    }
  }

  flash(msg) {
    if (!this.hasTimerTarget) return
    this.timerTarget.textContent = msg
  }

  fmt(ms) {
    const s = Math.max(0, Math.round(ms / 1000))
    const m = Math.floor(s / 60)
    const r = s % 60
    return `${m}:${String(r).padStart(2, "0")}`
  }
}
