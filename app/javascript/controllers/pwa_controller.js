import { Controller } from "@hotwired/stimulus"

// Mounted on <body> for signed-in users. Responsibilities:
//   1. Register /service-worker.js so the app installs as a PWA.
//   2. If the user opts in via the bell button, request notification
//      permission and POST the resulting subscription to the server.
//   3. Surface a one-time install prompt when the browser fires
//      beforeinstallprompt.
export default class extends Controller {
  static targets = ["enableBtn", "installBtn"]
  static values  = { vapidKey: String }

  async connect() {
    if (!("serviceWorker" in navigator)) return

    try {
      this.registration = await navigator.serviceWorker.register("/service-worker.js", { scope: "/" })
    } catch (e) {
      console.warn("[pwa] service worker register failed", e)
      return
    }

    window.addEventListener("beforeinstallprompt", (e) => {
      e.preventDefault()
      this.deferredInstall = e
      if (this.hasInstallBtnTarget) this.installBtnTarget.classList.remove("hidden")
    })

    if (this.hasEnableBtnTarget) {
      const sub = await this.registration.pushManager.getSubscription()
      this.reflectPushState(sub ? "on" : (Notification.permission === "denied" ? "blocked" : "off"))
    }
  }

  async installApp() {
    if (!this.deferredInstall) return
    this.deferredInstall.prompt()
    await this.deferredInstall.userChoice
    this.deferredInstall = null
    if (this.hasInstallBtnTarget) this.installBtnTarget.classList.add("hidden")
  }

  async togglePush() {
    const state = this.hasEnableBtnTarget ? this.enableBtnTarget.dataset.pushState : "off"
    if (state === "on") return this.disablePush()
    return this.enablePush()
  }

  async enablePush() {
    if (!this.registration) {
      alert("Service worker isn't ready yet — refresh and try again.")
      return
    }
    if (!this.vapidKeyValue) {
      alert("Push isn't configured yet on this server.")
      return
    }

    let permission = Notification.permission
    if (permission === "default") permission = await Notification.requestPermission()
    if (permission !== "granted") {
      this.reflectPushState(permission === "denied" ? "blocked" : "off")
      return
    }

    let sub = await this.registration.pushManager.getSubscription()
    if (!sub) {
      sub = await this.registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: this.urlBase64ToUint8Array(this.vapidKeyValue)
      })
    }

    await fetch("/push_subscriptions", {
      method: "POST",
      headers: this.headers(),
      credentials: "same-origin",
      body: JSON.stringify({ subscription: sub.toJSON() })
    })

    this.reflectPushState("on")
  }

  async disablePush() {
    if (!this.registration) return
    const sub = await this.registration.pushManager.getSubscription()
    if (sub) {
      await fetch("/push_subscriptions", {
        method: "DELETE",
        headers: this.headers(),
        credentials: "same-origin",
        body: JSON.stringify({ endpoint: sub.endpoint })
      })
      await sub.unsubscribe()
    }
    this.reflectPushState("off")
  }

  reflectPushState(state) {
    if (!this.hasEnableBtnTarget) return
    this.enableBtnTarget.dataset.pushState = state
    const labels = { on: "🔔 Notifications on", off: "🔕 Turn on push", blocked: "🚫 Blocked in browser" }
    this.enableBtnTarget.textContent = labels[state]
  }

  headers() {
    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
    }
  }

  urlBase64ToUint8Array(base64) {
    const padding = "=".repeat((4 - (base64.length % 4)) % 4)
    const b64 = (base64 + padding).replace(/-/g, "+").replace(/_/g, "/")
    const raw = atob(b64)
    const out = new Uint8Array(raw.length)
    for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i)
    return out
  }
}
