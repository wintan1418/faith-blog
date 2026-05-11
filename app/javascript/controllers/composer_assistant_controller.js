import { Controller } from "@hotwired/stimulus"

// Wires the two author-facing composer assistants: gentleness check and
// scripture suggestion. Both POST the current draft to a JSON endpoint and
// render the result in the panel below the toolbar. Neither blocks publish.
export default class extends Controller {
  static targets = ["panel", "panelContent", "gentlenessBtn", "scriptureBtn", "scriptureAutoBtn"]
  static values  = {
    gentlenessUrl: String,
    scriptureUrl:  String,
    csrf:          String
  }

  connect() {
    this.liveActive = localStorage.getItem("fc:liveScripture") === "1"
    this.updateAutoBtn()
    this.onDraftChange = this.onDraftChange.bind(this)
    this.element.addEventListener("input", this.onDraftChange)
  }

  disconnect() {
    if (this.onDraftChange) this.element.removeEventListener("input", this.onDraftChange)
    if (this._liveTimer) clearTimeout(this._liveTimer)
  }

  toggleAutoScripture(event) {
    event.preventDefault()
    this.liveActive = !this.liveActive
    localStorage.setItem("fc:liveScripture", this.liveActive ? "1" : "0")
    this.updateAutoBtn()
    if (this.liveActive) this.maybeAutoSuggest()
  }

  updateAutoBtn() {
    if (!this.hasScriptureAutoBtnTarget) return
    const btn = this.scriptureAutoBtnTarget
    btn.classList.toggle("is-on", this.liveActive)
    btn.setAttribute("aria-pressed", this.liveActive ? "true" : "false")
    const label = btn.querySelector(".fc-composer-asst-label")
    if (label) label.textContent = this.liveActive ? "Auto: on" : "Auto: off"
  }

  onDraftChange() {
    if (!this.liveActive) return
    if (this._liveTimer) clearTimeout(this._liveTimer)
    this._liveTimer = setTimeout(() => this.maybeAutoSuggest(), 1300)
  }

  async maybeAutoSuggest() {
    const text = this.draftText()
    if (text.length < 50) return
    // Cooldown — never fire more than once per ~8s, and skip if the manual
    // button is mid-flight so we don't double-spend on OpenAI.
    const now = Date.now()
    if (this._lastAutoAt && now - this._lastAutoAt < 8000) return
    if (this.hasScriptureBtnTarget && this.scriptureBtnTarget.disabled) return
    this._lastAutoAt = now

    this.markAutoBusy(true)
    try {
      const data = await this.post(this.scriptureUrlValue, { content: text })
      if (data && data.ok) this.renderScripture(data.verses || [])
      // Stay silent on errors in auto mode — the manual button is still there.
    } catch (e) {
      // silent
    } finally {
      this.markAutoBusy(false)
    }
  }

  markAutoBusy(busy) {
    if (!this.hasScriptureAutoBtnTarget) return
    this.scriptureAutoBtnTarget.classList.toggle("is-busy", busy)
  }

  async checkGentleness() {
    const text = this.draftText()
    if (text.length < 20) {
      this.showError("Type a few more words first — I need something to read.")
      return
    }

    this.busy(this.gentlenessBtnTarget, "Checking…")
    try {
      const data = await this.post(this.gentlenessUrlValue, { content: text })
      if (!data.ok) {
        this.showError(data.error || "Couldn't run the check right now.")
      } else {
        this.renderGentleness(data)
      }
    } catch (e) {
      this.showError("Couldn't reach the gentleness check. Try again in a moment.")
    } finally {
      this.idle(this.gentlenessBtnTarget, "Check tone")
    }
  }

  async suggestScripture() {
    const text = this.draftText()
    if (text.length < 40) {
      this.showError("Write a couple of sentences first so I can find a fitting verse.")
      return
    }

    this.busy(this.scriptureBtnTarget, "Searching…")
    try {
      const data = await this.post(this.scriptureUrlValue, { content: text })
      if (!data.ok) {
        this.showError(data.error || "Couldn't suggest scripture right now.")
      } else {
        this.renderScripture(data.verses || [])
      }
    } catch (e) {
      this.showError("Couldn't reach the scripture suggester. Try again in a moment.")
    } finally {
      this.idle(this.scriptureBtnTarget, "Suggest scripture")
    }
  }

  renderGentleness({ tone, summary, nudge, suggestion }) {
    const labels = { gentle: "🕊️ Reads gently", firm: "💬 Firm but ok", harsh: "⚠️ Could land hard" }
    let html = `<div class="fc-asst-result is-${tone}">`
    html += `<p class="fc-asst-headline">${labels[tone] || tone}</p>`
    if (summary) html += `<p class="fc-asst-line">${this.escape(summary)}</p>`
    if (nudge)   html += `<p class="fc-asst-nudge">${this.escape(nudge)}</p>`
    if (suggestion) {
      html += `<div class="fc-asst-suggest"><span>Softer reframe:</span><blockquote>${this.escape(suggestion)}</blockquote></div>`
    }
    html += `</div>`
    this.show(html)
  }

  renderScripture(verses) {
    if (!verses.length) {
      this.show(`<div class="fc-asst-result is-empty"><p class="fc-asst-line">No fitting verse jumped out — try writing a bit more about what's on your heart.</p></div>`)
      return
    }
    let html = `<div class="fc-asst-result is-scripture"><p class="fc-asst-headline">📖 Suggested scripture</p><ul class="fc-asst-verses">`
    for (const v of verses) {
      html += `<li><a href="/scripture/lookup?reference=${encodeURIComponent(v.reference)}" data-controller="scripture" data-action="mouseenter->scripture#hoverPreview" class="fc-asst-verse-ref">${this.escape(v.reference)}</a>`
      if (v.reason) html += ` — <span class="fc-asst-verse-reason">${this.escape(v.reason)}</span>`
      html += `</li>`
    }
    html += `</ul></div>`
    this.show(html)
  }

  showError(msg) {
    this.show(`<div class="fc-asst-result is-error"><p class="fc-asst-line">${this.escape(msg)}</p></div>`)
  }

  show(html) {
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.remove("hidden")
    this.panelContentTarget.innerHTML = html
  }

  draftText() {
    const editor = this.element.querySelector("trix-editor")
    if (editor && editor.editor) return editor.editor.getDocument().toString().trim()
    const ta = this.element.querySelector("textarea, input[name='post[content]']")
    return ta ? ta.value.trim() : ""
  }

  async post(url, body) {
    const resp = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfValue || document.querySelector('meta[name="csrf-token"]')?.content || ""
      },
      body: JSON.stringify(body),
      credentials: "same-origin"
    })
    return resp.json()
  }

  busy(btn, label) {
    if (!btn) return
    btn.disabled = true
    btn.dataset.originalLabel = btn.dataset.originalLabel || btn.textContent.trim()
    btn.textContent = label
  }

  idle(btn) {
    if (!btn) return
    btn.disabled = false
    if (btn.dataset.originalLabel) btn.textContent = btn.dataset.originalLabel
  }

  escape(s) {
    return String(s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"})[c])
  }
}
