import { Controller } from "@hotwired/stimulus"

// Simple play / pause / seek for the voice-note banner. The total
// duration is rendered from the server (post.voice_duration_ms) so
// the time reads correctly before the audio metadata loads.
export default class extends Controller {
  static targets = ["audio", "playBtn", "current", "total", "progress", "fill"]
  static values  = { duration: Number }

  connect() {
    this.playing = false
    this.audioTarget.preload = "metadata"
    this.bound = {
      timeupdate: () => this.onTimeUpdate(),
      ended:      () => this.onEnded(),
      loaded:     () => this.onLoaded()
    }
    this.audioTarget.addEventListener("timeupdate", this.bound.timeupdate)
    this.audioTarget.addEventListener("ended", this.bound.ended)
    this.audioTarget.addEventListener("loadedmetadata", this.bound.loaded)

    if (this.durationValue > 0) {
      this.totalTarget.textContent = this.fmt(this.durationValue / 1000)
    }
  }

  disconnect() {
    this.audioTarget.removeEventListener("timeupdate", this.bound.timeupdate)
    this.audioTarget.removeEventListener("ended", this.bound.ended)
    this.audioTarget.removeEventListener("loadedmetadata", this.bound.loaded)
    this.audioTarget.pause()
  }

  toggle(event) {
    event?.preventDefault()
    if (this.audioTarget.paused) {
      this.audioTarget.play().catch(() => {})
    } else {
      this.audioTarget.pause()
    }
    this.playing = !this.audioTarget.paused
    this.element.classList.toggle("is-playing", this.playing)
  }

  seek(event) {
    if (!this.duration()) return
    const rect = this.progressTarget.getBoundingClientRect()
    const x = (event.clientX ?? event.touches?.[0]?.clientX ?? 0) - rect.left
    const pct = Math.max(0, Math.min(1, x / rect.width))
    this.audioTarget.currentTime = pct * this.duration()
  }

  onTimeUpdate() {
    const cur = this.audioTarget.currentTime || 0
    const dur = this.duration()
    this.currentTarget.textContent = this.fmt(cur)
    if (dur > 0) {
      const pct = (cur / dur) * 100
      this.fillTarget.style.width = `${pct}%`
    }
  }

  onLoaded() {
    const real = this.audioTarget.duration
    if (Number.isFinite(real) && real > 0) {
      this.totalTarget.textContent = this.fmt(real)
    }
  }

  onEnded() {
    this.element.classList.remove("is-playing")
    this.playing = false
    this.fillTarget.style.width = "0%"
    this.currentTarget.textContent = "0:00"
  }

  duration() {
    const real = this.audioTarget.duration
    if (Number.isFinite(real) && real > 0) return real
    if (this.durationValue > 0) return this.durationValue / 1000
    return 0
  }

  fmt(seconds) {
    const s = Math.max(0, Math.round(seconds))
    const m = Math.floor(s / 60)
    const r = s % 60
    return `${m}:${String(r).padStart(2, "0")}`
  }
}
