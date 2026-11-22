import { Controller } from "@hotwired/stimulus"

// The LinkedIn-style "New posts" pill at the top of the feed.
//
// The server says how many posts this member hasn't seen that are newer than
// the feed on screen (sinceValue = when the page was built), with up to three
// author faces (GET urlValue → feed/_new_posts_pill). We ask:
//   - when the feed appears (covers a feed restored from cache, or an app
//     web view left open since the last visit),
//   - when the tab/app comes back to the front,
//   - when a live marker lands in the hidden bucket (#feed_incoming, filled
//     by the "feed:public" Turbo stream whenever a post goes live).
// Asking the server (instead of counting markers) keeps blocked people,
// held posts and the member's own posts out, and never shows who wrote an
// anonymous post.
//
// Tapping the pill scrolls to the top and reloads just the feed frame: the
// unseen posts come first with a small "New" dot, and the pill goes away.
export default class extends Controller {
  static targets = ["bucket", "pill"]
  static values = { url: String, since: Number, feedUrl: String }

  connect() {
    this.onVisible = () => { if (document.visibilityState === "visible") this.check() }
    document.addEventListener("visibilitychange", this.onVisible)
    if (this.hasBucketTarget) {
      this.observer = new MutationObserver(() => this.scheduleCheck())
      this.observer.observe(this.bucketTarget, { childList: true })
    }
    this.check()
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
    document.removeEventListener("visibilitychange", this.onVisible)
    clearTimeout(this.timer)
  }

  // A burst of markers (or several at once) → one request.
  scheduleCheck() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.check(), 400)
  }

  async check() {
    if (!this.hasPillTarget || !this.urlValue) return
    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("since", this.sinceValue)
      const response = await fetch(url, { headers: { Accept: "text/html" }, credentials: "same-origin" })
      if (!response.ok) return
      const html = await response.text()
      if (!this.element.isConnected) return
      this.pillTarget.innerHTML = html
      const inner = this.pillTarget.querySelector("[data-new-posts-count]")
      const count = inner ? parseInt(inner.dataset.newPostsCount, 10) || 0 : 0
      this.pillTarget.classList.toggle("hidden", count === 0)
      this.pillTarget.setAttribute("aria-label", count ? `Show ${count} new post${count === 1 ? "" : "s"}` : "")
    } catch (_) {
      // Offline or the request failed: leave the pill as it is.
    }
  }

  flush(event) {
    event.preventDefault()
    this.pillTarget.classList.add("hidden")
    window.scrollTo({ top: 0, behavior: "smooth" })
    const url = this.feedUrlValue || "/feed"
    const frame = document.getElementById("feed_stream")
    if (window.Turbo && frame) {
      window.Turbo.visit(url, { frame: "feed_stream", action: "advance" })
    } else {
      window.location.href = url
    }
  }
}
