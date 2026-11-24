import { Controller } from "@hotwired/stimulus"

// The composer's "Part of a series" control. Picking "New series…" reveals
// a name field. While the title is typed, asks the server whether it looks
// like the next part of something this writer already posted ("(Part 4)",
// "#3", "Day 2") and, if so, offers to add it to that series.
export default class extends Controller {
  static targets = ["select", "newWrap", "newTitle", "adopt", "hint", "hintText"]
  static values = { url: String, postId: String }

  connect() {
    this.dismissed = new Set()
    this.changed()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.abort?.abort()
  }

  changed() {
    if (!this.hasSelectTarget) return
    const isNew = this.selectTarget.value === "new"
    this.newWrapTarget.classList.toggle("hidden", !isNew)
    if (!isNew && this.hasAdoptTarget) this.adoptTarget.value = ""
    if (this.selectTarget.value !== "") this.hideHint()
  }

  titleChanged(event) {
    clearTimeout(this.timer)
    const title = event.target.value.trim()
    this.timer = setTimeout(() => this.lookup(title), 450)
  }

  async lookup(title) {
    if (!this.hasSelectTarget || !this.hasUrlValue || this.selectTarget.value !== "" || title.length < 4) {
      this.hideHint()
      return
    }
    this.abort?.abort()
    this.abort = new AbortController()
    const params = new URLSearchParams({ title })
    if (this.postIdValue) params.set("post_id", this.postIdValue)
    try {
      const resp = await fetch(`${this.urlValue}?${params}`, {
        headers: { Accept: "application/json" },
        signal: this.abort.signal,
        credentials: "same-origin"
      })
      if (!resp.ok) return this.hideHint()
      const data = await resp.json()
      this.show(data.suggestion)
    } catch (_e) {
      // Aborted by a newer keystroke, or offline: no hint is fine.
    }
  }

  show(suggestion) {
    if (!suggestion || this.dismissed.has(suggestion.title.toLowerCase()) || this.selectTarget.value !== "") {
      return this.hideHint()
    }
    this.suggestion = suggestion
    const part = suggestion.part ? `part ${suggestion.part}` : "the next part"
    const earlier = suggestion.post_ids.length
    this.hintTextTarget.textContent = suggestion.series_id
      ? `Looks like ${part} of “${suggestion.title}”. Add it to that series?`
      : `Looks like ${part} of “${suggestion.title}”. Start a series with your ${earlier === 1 ? "earlier part" : `${earlier} earlier parts`}?`
    this.hintTarget.classList.remove("hidden")
  }

  accept() {
    const s = this.suggestion
    if (!s) return
    if (s.series_id) {
      this.selectTarget.value = String(s.series_id)
      if (this.hasAdoptTarget) this.adoptTarget.value = ""
    } else {
      this.selectTarget.value = "new"
      this.newTitleTarget.value = s.title
    }
    this.changed()
    // After changed(): it clears the list when leaving "new".
    if (this.hasAdoptTarget) this.adoptTarget.value = s.post_ids.join(",")
    this.hideHint()
  }

  dismiss() {
    if (this.suggestion) this.dismissed.add(this.suggestion.title.toLowerCase())
    this.hideHint()
  }

  hideHint() {
    if (this.hasHintTarget) this.hintTarget.classList.add("hidden")
  }
}
