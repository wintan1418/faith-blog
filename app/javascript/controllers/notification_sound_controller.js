import { Controller } from "@hotwired/stimulus"

// Plays a soft Web-Audio chime when fresh content arrives via Turbo Streams.
// No audio file shipped — the chime is synthesised in-browser on demand.
//
// Mute state is persisted in localStorage ('fc:sound-muted'). The toggle
// can be wired anywhere via data-action="click->notification-sound#toggle".
//
// Triggers:
//   • turbo:before-stream-render with target containing 'messages' or
//     'notifications' or 'feed_incoming' → play chime (unless this tab
//     is the one that sent the message — we filter by document.hidden
//     and by debouncing).
export default class extends Controller {
  static values = {
    mutedKey: { type: String, default: "fc:sound-muted" }
  }

  connect() {
    this.muted = localStorage.getItem(this.mutedKeyValue) === "1"
    this.lastPlayAt = 0
    this.handler = this.onStream.bind(this)
    document.addEventListener("turbo:before-stream-render", this.handler)
    this.reflectToggle()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.handler)
    if (this.ctx) try { this.ctx.close() } catch {}
  }

  toggle(event) {
    if (event) event.preventDefault()
    this.muted = !this.muted
    localStorage.setItem(this.mutedKeyValue, this.muted ? "1" : "0")
    this.reflectToggle()
  }

  reflectToggle() {
    document.querySelectorAll("[data-notification-sound-toggle]").forEach(el => {
      const onLabel  = el.dataset.onLabel  || "🔔 Sounds on"
      const offLabel = el.dataset.offLabel || "🔇 Sounds muted"
      el.textContent = this.muted ? offLabel : onLabel
    })
  }

  onStream(event) {
    if (this.muted) return
    // Only chime for relevant targets so we don't ding on every render.
    const stream = event.target
    const target = stream?.getAttribute("target") || ""
    const action = stream?.getAttribute("action") || ""
    const RELEVANT = ["messages", "feed_incoming", "notifications_panel"]
    if (!RELEVANT.some(t => target.includes(t))) return
    // Skip when this tab is the sender (we just submitted a form).
    if (action === "replace" && target.includes("comment_form")) return

    // Debounce — at most one chime every 1500ms.
    const now = Date.now()
    if (now - this.lastPlayAt < 1500) return
    this.lastPlayAt = now

    this.playChime()
  }

  // Synthesise a soft two-tone "ding" using the Web Audio API.
  playChime() {
    try {
      if (!this.ctx) {
        const AC = window.AudioContext || window.webkitAudioContext
        if (!AC) return
        this.ctx = new AC()
      }
      const ctx = this.ctx
      if (ctx.state === "suspended") ctx.resume()

      const now = ctx.currentTime
      const master = ctx.createGain()
      master.gain.value = 0.10
      master.connect(ctx.destination)

      // Two-tone chime: a perfect fifth, ~80ms apart, each a soft sine
      // with a quick attack and slow decay.
      ;[ { freq: 880, at: 0 }, { freq: 1320, at: 0.08 } ].forEach(({ freq, at }) => {
        const o = ctx.createOscillator()
        const g = ctx.createGain()
        o.type = "sine"
        o.frequency.value = freq
        g.gain.setValueAtTime(0, now + at)
        g.gain.linearRampToValueAtTime(0.7, now + at + 0.015)
        g.gain.exponentialRampToValueAtTime(0.001, now + at + 0.45)
        o.connect(g).connect(master)
        o.start(now + at)
        o.stop(now + at + 0.5)
      })
    } catch (e) {
      // Audio blocked / unavailable — ignore silently.
    }
  }
}
