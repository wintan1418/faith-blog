import { Controller } from "@hotwired/stimulus"
import { copyText } from "../copy_text"

// Small outline icons (same 24px grid and stroke as render_icon) — no emoji.
const ICON_PATHS = {
  book:   "M2 4h6a4 4 0 0 1 4 4v13a3 3 0 0 0-3-3H2zM22 4h-6a4 4 0 0 0-4 4v13a3 3 0 0 1 3-3h7z",
  dove:   "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM8 14s1.5 2 4 2 4-2 4-2M9 9h.01M15 9h.01",
  firm:   "M21 11.5a8.4 8.4 0 0 1-9 8.5 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7A8.4 8.4 0 0 1 12 3a8.4 8.4 0 0 1 9 8.5z",
  alert:  "M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0zM12 9v4M12 17h.01",
  copy:   "M10 8h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H10a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2zM4 16a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2",
  check:  "M20 6 9 17l-5-5",
  plus:   "M12 5v14M5 12h14",
  x:      "M18 6 6 18M6 6l12 12"
}
const icon = (name, cls = "eg-asst-icon") =>
  `<svg class="${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${ICON_PATHS[name]}"/></svg>`

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
    const box = event.currentTarget
    if (box && box.type === "checkbox") {
      this.liveActive = box.checked
    } else {
      event.preventDefault()
      this.liveActive = !this.liveActive
    }
    localStorage.setItem("fc:liveScripture", this.liveActive ? "1" : "0")
    this.updateAutoBtn()
    if (this.liveActive) this.maybeAutoSuggest()
  }

  updateAutoBtn() {
    if (!this.hasScriptureAutoBtnTarget) return
    const btn = this.scriptureAutoBtnTarget
    btn.classList.toggle("is-on", this.liveActive)
    // The composer uses a switch (checkbox); the edit page a toggle button.
    if (btn.type === "checkbox") {
      btn.checked = this.liveActive
      return
    }
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
    const labels = {
      gentle: `${icon("dove")} Reads gently`,
      firm:   `${icon("firm")} Firm but OK`,
      harsh:  `${icon("alert")} Could land hard`
    }
    let html = `<div class="fc-asst-result is-${this.escape(tone)}">`
    html += `<div class="eg-asst-head"><p class="fc-asst-headline">${labels[tone] || this.escape(tone)}</p>${this.dismissButton()}</div>`
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
      this.show(`<div class="fc-asst-result is-empty"><div class="eg-asst-head"><p class="fc-asst-line">No fitting verse jumped out — try writing a bit more about what's on your heart.</p>${this.dismissButton()}</div></div>`)
      return
    }
    let html = `<div class="fc-asst-result is-scripture"><ul class="fc-asst-verses">`
    verses.forEach((v, i) => {
      const text = (v.text || "").trim()
      const trans = v.translation || "KJV"
      const clip = text ? `"${text}"\n— ${v.reference} (${trans})` : `${v.reference} (${trans})`
      html += `<li class="fc-asst-verse">
        <figure class="eg-asst-verse">
          ${icon("book", "eg-asst-verse-icon")}
          <span class="eg-asst-verse-body">`
      if (text) html += `<blockquote class="fc-asst-verse-text">${this.escape(text)}</blockquote>`
      html += `<figcaption class="eg-asst-verse-ref">${this.escape(v.reference)} · ${this.escape(trans)} · Suggested</figcaption>`
      if (v.reason) html += `<p class="fc-asst-verse-reason">${this.escape(v.reason)}</p>`
      html += `<span class="eg-asst-verse-actions">
              <button type="button" class="eg-asst-link"
                      data-action="click->composer-assistant#insertVerse"
                      data-copy-text="${this.escape(clip)}">${icon("plus")}<span>Add to breath</span></button>
              <button type="button" class="fc-copy-btn eg-asst-link"
                      data-action="click->composer-assistant#copyVerse"
                      data-copy-text="${this.escape(clip)}"
                      title="Copy verse">${icon("copy")}<span>Copy</span></button>
            </span>
          </span>
          ${i === 0 ? this.dismissButton("Remove verse") : ""}
        </figure>
      </li>`
    })
    html += `</ul></div>`
    this.show(html)
  }

  async copyVerse(event) {
    event.preventDefault()
    const btn = event.currentTarget
    const text = btn.dataset.copyText || ""
    if (!text) return
    const ok = await copyText(text)
    btn.classList.toggle("is-copied", ok)
    btn.innerHTML = ok ? `${icon("check")}<span>Copied</span>` : `${icon("x")}<span>Couldn't copy</span>`
    setTimeout(() => {
      btn.classList.remove("is-copied")
      btn.innerHTML = `${icon("copy")}<span>Copy</span>`
    }, 1400)
  }

  // Put a suggested verse at the end of the breath.
  insertVerse(event) {
    event.preventDefault()
    const text = event.currentTarget.dataset.copyText || ""
    const el = this.element.querySelector("trix-editor")
    if (!text) return
    if (!el || !el.editor) {
      const ta = this.element.querySelector("textarea")
      if (!ta) return
      ta.value = ta.value.trim() ? `${ta.value.trimEnd()}\n\n${text}` : text
      ta.dispatchEvent(new Event("input", { bubbles: true }))
      return this.dismiss()
    }
    const doc = el.editor.getDocument().toString().trim()
    el.editor.setSelectedRange([ el.editor.getDocument().getLength() - 1, el.editor.getDocument().getLength() - 1 ])
    el.editor.insertString((doc ? "\n\n" : "") + text)
    this.dismiss()
  }

  dismiss(event) {
    if (event) event.preventDefault()
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.add("hidden")
    this.panelContentTarget.innerHTML = ""
  }

  dismissButton(label = "Dismiss") {
    return `<button type="button" class="eg-asst-dismiss" data-action="click->composer-assistant#dismiss" aria-label="${label}" title="${label}">${icon("x")}</button>`
  }

  showError(msg) {
    this.show(`<div class="fc-asst-result is-error"><div class="eg-asst-head"><p class="fc-asst-line">${this.escape(msg)}</p>${this.dismissButton()}</div></div>`)
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

  // Only the button's words change (a [data-label] span when there is one),
  // so its icon stays put.
  busy(btn, label) {
    if (!btn) return
    const words = btn.querySelector("[data-label]") || btn
    btn.disabled = true
    btn.setAttribute("aria-busy", "true")
    btn.dataset.originalLabel = btn.dataset.originalLabel || words.textContent.trim()
    words.textContent = label
  }

  idle(btn) {
    if (!btn) return
    const words = btn.querySelector("[data-label]") || btn
    btn.disabled = false
    btn.removeAttribute("aria-busy")
    if (btn.dataset.originalLabel) words.textContent = btn.dataset.originalLabel
  }

  escape(s) {
    return String(s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"})[c])
  }
}
