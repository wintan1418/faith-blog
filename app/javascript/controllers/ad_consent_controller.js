import { Controller } from "@hotwired/stimulus"

// Cookie choice + Meta Pixel / Google tag. Nothing loads before consent where consent is
// required (Europe, UK); elsewhere tags load unless the visitor said no.
// The choice is kept in localStorage ("fc-ad-consent": "granted" | "denied").
const KEY = "fc-ad-consent"

export default class extends Controller {
  static targets = ["banner"]
  static values = { pixel: String, gtag: String, conversion: String, required: Boolean, signup: Boolean }

  connect() {
    if (document.documentElement.hasAttribute("data-turbo-preview")) return
    const choice = this.choice()
    if (choice === "granted" || (choice === null && !this.requiredValue)) {
      this.load()
    } else if (choice === null) {
      this.bannerTarget.hidden = false
    }
    window.addEventListener("fc:cookie-settings", this.reopen)
  }

  disconnect() {
    window.removeEventListener("fc:cookie-settings", this.reopen)
  }

  accept() { this.save("granted"); this.bannerTarget.hidden = true; this.load() }

  decline() {
    this.save("denied")
    this.bannerTarget.hidden = true
    if (window.gtag) window.gtag("consent", "update", { ad_storage: "denied", ad_user_data: "denied", ad_personalization: "denied", analytics_storage: "denied" })
    if (window.fbq) window.fbq("consent", "revoke")
  }

  reopen = () => { this.bannerTarget.hidden = false }

  choice() {
    try { return localStorage.getItem(KEY) } catch { return null }
  }

  save(value) {
    try { localStorage.setItem(KEY, value) } catch {}
  }

  // Scripts are added once per visit; Turbo keeps them, so later pages only send a page view.
  load() {
    const first = !window.__fcAdsLoaded
    window.__fcAdsLoaded = true
    if (first) {
      if (this.gtagValue) this.loadGoogle()
      if (this.pixelValue) this.loadMeta()
    } else {
      if (window.gtag && this.gtagValue) window.gtag("event", "page_view", { page_location: location.href, page_title: document.title })
      if (window.fbq) window.fbq("track", "PageView")
    }
    if (this.signupValue) this.trackSignup()
  }

  loadGoogle() {
    window.dataLayer = window.dataLayer || []
    window.gtag = function () { window.dataLayer.push(arguments) }
    window.gtag("consent", "default", { ad_storage: "granted", ad_user_data: "granted", ad_personalization: "granted", analytics_storage: "granted" })
    window.gtag("js", new Date())
    window.gtag("config", this.gtagValue)
    const conversionAccount = this.conversionValue.split("/")[0]
    if (conversionAccount && conversionAccount !== this.gtagValue) window.gtag("config", conversionAccount)
    const s = document.createElement("script")
    s.async = true
    s.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(this.gtagValue)}`
    document.head.appendChild(s)
  }

  loadMeta() {
    /* Meta's standard base code, unminified. */
    if (window.fbq) return
    const fbq = function () { fbq.callMethod ? fbq.callMethod.apply(fbq, arguments) : fbq.queue.push(arguments) }
    window.fbq = window._fbq = fbq
    fbq.push = fbq; fbq.loaded = true; fbq.version = "2.0"; fbq.queue = []
    const s = document.createElement("script")
    s.async = true
    s.src = "https://connect.facebook.net/en_US/fbevents.js"
    document.head.appendChild(s)
    fbq("init", this.pixelValue)
    fbq("track", "PageView")
  }

  trackSignup() {
    if (window.fbq) window.fbq("track", "CompleteRegistration")
    if (window.gtag) {
      window.gtag("event", "sign_up", { method: "brethreign" })
      if (this.conversionValue) window.gtag("event", "conversion", { send_to: this.conversionValue })
    }
  }
}
