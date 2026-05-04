import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["lightIcon", "darkIcon"]

  connect() {
    this.applyTheme()

    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      if (localStorage.getItem("fc-dark") === null && localStorage.getItem("theme") === null) {
        this.applyTheme()
      }
    })
  }

  toggle() {
    const dark = !document.documentElement.classList.contains("theme-dark")
    localStorage.setItem("fc-dark", dark ? "1" : "0")
    localStorage.setItem("theme", dark ? "dark" : "light")
    this.apply(dark)
    this.persist(dark)
  }

  applyTheme() {
    const saved = localStorage.getItem("fc-dark")
    const legacyTheme = localStorage.getItem("theme")
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    const dark = saved === null
      ? (legacyTheme ? legacyTheme === "dark" : prefersDark)
      : saved === "1"

    this.apply(dark)
  }

  apply(dark) {
    const html = document.documentElement
    const body = document.body

    html.dataset.theme = dark ? "dark" : "light"
    html.classList.toggle("theme-dark", dark)
    html.classList.toggle("theme-light", !dark)

    if (body) {
      body.classList.toggle("theme-dark", dark)
      body.classList.toggle("theme-light", !dark)
      body.style.removeProperty("background-color")
      body.style.removeProperty("color")
    }

    this.updateIcons()
  }

  updateIcons() {
    const isDark = document.documentElement.classList.contains("theme-dark")

    if (this.hasLightIconTarget && this.hasDarkIconTarget) {
      this.lightIconTarget.classList.toggle("hidden", isDark)
      this.darkIconTarget.classList.toggle("hidden", !isDark)
    }
  }

  persist(dark) {
    const token = document.querySelector("meta[name='csrf-token']")?.content

    fetch("/settings/dark_mode", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        ...(token ? { "X-CSRF-Token": token } : {})
      },
      body: JSON.stringify({ dark })
    }).catch(() => {})
  }
}
