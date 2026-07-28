import { Controller } from "@hotwired/stimulus"

// Segmented feed tabs with a gliding pill: a "thumb" element sits behind the
// active tab and slides to whichever tab is tapped, instead of the highlight
// just teleporting. The tabs live inside the feed_stream turbo-frame, so on
// every frame swap this controller reconnects and snaps the thumb (no
// animation) to the freshly-rendered active tab.
export default class extends Controller {
  connect() {
    this.thumb = document.createElement("span")
    this.thumb.className = "fc-tab-thumb"
    this.thumb.setAttribute("aria-hidden", "true")
    this.element.prepend(this.thumb)
    this.element.classList.add("has-thumb")

    this.onResize = () => this.place(this.activeTab(), false)
    window.addEventListener("resize", this.onResize)

    // Fonts shifting widths after first paint would leave the thumb misplaced.
    requestAnimationFrame(() => this.place(this.activeTab(), false))
  }

  disconnect() {
    window.removeEventListener("resize", this.onResize)
    this.thumb?.remove()
    this.element.classList.remove("has-thumb")
  }

  activeTab() {
    return this.element.querySelector(".fc-tab.is-active")
  }

  // Fired on tab click — highlight moves instantly while the frame loads.
  move(event) {
    const tab = event.currentTarget
    this.element.querySelectorAll(".fc-tab").forEach(t => t.classList.toggle("is-active", t === tab))
    this.place(tab, true)
  }

  place(tab, animate) {
    if (!tab) { this.thumb.style.opacity = "0"; return }
    const tabRect = tab.getBoundingClientRect()
    const barRect = this.element.getBoundingClientRect()
    if (tabRect.width === 0) return

    if (!animate) this.thumb.style.transition = "none"
    this.thumb.style.opacity = "1"
    this.thumb.style.width = `${tabRect.width}px`
    this.thumb.style.transform = `translateX(${tabRect.left - barRect.left + this.element.scrollLeft}px)`
    if (!animate) requestAnimationFrame(() => { this.thumb.style.transition = "" })
  }
}
