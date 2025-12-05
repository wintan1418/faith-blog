import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["lightIcon", "darkIcon"]

  connect() {
    // Apply theme immediately on connect
    this.applyTheme()
    
    // Listen for system theme changes
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      if (!localStorage.getItem("theme")) {
        this.applyTheme()
      }
    })
  }

  toggle() {
    const isDark = document.documentElement.classList.contains("dark")
    
    if (isDark) {
      document.documentElement.classList.remove("dark")
      localStorage.setItem("theme", "light")
    } else {
      document.documentElement.classList.add("dark")
      localStorage.setItem("theme", "dark")
    }
    
    this.updateIcons()
  }

  applyTheme() {
    const savedTheme = localStorage.getItem("theme")
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches

    if (savedTheme === "dark" || (!savedTheme && prefersDark)) {
      document.documentElement.classList.add("dark")
    } else {
      document.documentElement.classList.remove("dark")
    }
    
    this.updateIcons()
  }

  updateIcons() {
    const isDark = document.documentElement.classList.contains("dark")
    
    if (this.hasLightIconTarget && this.hasDarkIconTarget) {
      // Light icon (moon) - show when in light mode
      this.lightIconTarget.classList.toggle("hidden", isDark)
      // Dark icon (sun) - show when in dark mode
      this.darkIconTarget.classList.toggle("hidden", !isDark)
    }
  }
}
