import { Controller } from "@hotwired/stimulus"

// City picker: type a few letters, pick a real city (keyboard or tap).
// "Use my location" asks the browser once, sends a rounded position to find the
// nearest city, and keeps nothing but that city.
const PIN = '<svg class="cp-option-pin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M12 21s-7-6.2-7-11.5a7 7 0 0 1 14 0C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.4"/></svg>'
const CHECK = '<svg class="cp-option-check" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>'

export default class extends Controller {
  static targets = ["input", "id", "list", "status", "locate"]
  static values = { url: String, nearestUrl: String, country: String, autosubmit: Boolean }

  connect() {
    this.results = []
    this.active = -1
    if (this.idTarget.value) this.pickedLabel = this.inputTarget.value
    if (this.hasLocateTarget && navigator.geolocation && window.isSecureContext) this.locateTarget.hidden = false
  }

  disconnect() {
    clearTimeout(this.timer)
    this.request?.abort()
  }

  search() {
    // Typing changes the place: the saved city no longer applies until one is picked.
    if (this.inputTarget.value !== this.pickedLabel) this.idTarget.value = ""
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fetchResults(), 150)
  }

  async fetchResults() {
    const q = this.inputTarget.value.trim()
    if (q.length < 2) return this.close()

    this.request?.abort()
    this.request = new AbortController()
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", q)
    if (this.countryValue) url.searchParams.set("country", this.countryValue)
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: this.request.signal })
      if (!response.ok) return
      this.results = await response.json()
      this.render()
    } catch (error) {
      if (error.name !== "AbortError") this.close()
    }
  }

  render() {
    this.listTarget.innerHTML = ""
    this.active = -1
    if (this.results.length === 0) {
      this.listTarget.innerHTML = `<li class="cp-empty" role="option" aria-disabled="true">No city found. Try the nearest big town.</li>`
    } else {
      const typed = this.inputTarget.value.split(",")[0].trim()
      this.results.forEach((city, index) => {
        const li = document.createElement("li")
        li.id = `${this.listTarget.id}-${index}`
        li.className = "cp-option"
        li.setAttribute("role", "option")
        const selected = String(city.id) === String(this.idTarget.value)
        li.setAttribute("aria-selected", String(selected))
        li.insertAdjacentHTML("afterbegin", PIN)
        const text = document.createElement("span")
        text.className = "cp-option-text"
        const name = document.createElement("span")
        name.className = "cp-option-name"
        // The letters typed so far, in mint.
        if (typed && city.name.toLowerCase().startsWith(typed.toLowerCase())) {
          const mark = document.createElement("mark")
          mark.textContent = city.name.slice(0, typed.length)
          name.append(mark, city.name.slice(typed.length))
        } else {
          name.textContent = city.name
        }
        const where = document.createElement("span")
        where.className = "cp-option-where"
        const count = city.breathers > 0 ? ` · ${city.breathers} ${city.breathers === 1 ? "breather" : "breathers"}` : ""
        where.textContent = [city.region, city.country].filter(Boolean).join(", ") + count
        text.append(name, where)
        li.append(text)
        if (selected) li.insertAdjacentHTML("beforeend", CHECK)
        // mousedown, not click: the input's blur would close the list first.
        li.addEventListener("mousedown", (event) => { event.preventDefault(); this.choose(index) })
        this.listTarget.append(li)
      })
    }
    this.open()
  }

  keydown(event) {
    const open = !this.listTarget.hidden && this.results.length > 0
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        if (!open) return this.fetchResults()
        this.highlight(Math.min(this.active + 1, this.results.length - 1))
        break
      case "ArrowUp":
        if (!open) return
        event.preventDefault()
        this.highlight(Math.max(this.active - 1, 0))
        break
      case "Enter":
        if (open) {
          event.preventDefault()
          this.choose(this.active >= 0 ? this.active : 0)
        }
        break
      case "Escape":
        if (open) { event.preventDefault(); this.close() }
        break
    }
  }

  highlight(index) {
    this.active = index
    this.listTarget.querySelectorAll(".cp-option").forEach((li, i) => {
      li.classList.toggle("is-active", i === index)
      if (i === index) li.scrollIntoView({ block: "nearest" })
    })
    this.inputTarget.setAttribute("aria-activedescendant", `${this.listTarget.id}-${index}`)
  }

  choose(index) {
    const city = this.results[index]
    if (!city) return
    this.pick(city)
  }

  pick(city) {
    this.idTarget.value = city.id
    this.inputTarget.value = city.label
    this.pickedLabel = city.label
    this.close()
    this.dispatch("picked", { detail: city })
    if (this.autosubmitValue) {
      this.status(`${city.label} selected.`, "ok")
      this.element.closest("form")?.requestSubmit()
    } else {
      this.status(`${city.label}. Tap Save to keep it.`, "ok")
      this.nudgeSave()
    }
  }

  // Point at the form's Save button after a city is picked, so it isn't missed.
  nudgeSave() {
    const save = this.element.closest("form")?.querySelector("[type=submit]")
    if (!save) return
    save.classList.remove("cp-save-nudge")
    void save.offsetWidth
    save.classList.add("cp-save-nudge")
    setTimeout(() => save.classList.remove("cp-save-nudge"), 4000)
  }

  blur() {
    setTimeout(() => this.close(), 120)
  }

  open() {
    this.listTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    if (!this.hasListTarget) return
    this.listTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  locate() {
    if (!navigator.geolocation) return this.status("Your browser can't share a location. Type your city instead.", "error")
    this.status("Finding your city…")
    this.locateTarget.disabled = true
    navigator.geolocation.getCurrentPosition(
      (position) => this.sendPosition(position.coords),
      (error) => { this.locateTarget.disabled = false; this.status(this.locationError(error), "error") },
      { enableHighAccuracy: false, timeout: 10000, maximumAge: 600000 }
    )
  }

  async sendPosition(coords) {
    // Two decimals (about 1 km) is plenty to find a city; nothing more leaves the phone.
    const body = new FormData()
    body.set("lat", coords.latitude.toFixed(2))
    body.set("lng", coords.longitude.toFixed(2))
    const token = document.querySelector("meta[name=csrf-token]")?.content || ""
    try {
      const response = await fetch(this.nearestUrlValue, {
        method: "POST", body, credentials: "same-origin",
        headers: { Accept: "application/json", "X-CSRF-Token": token }
      })
      if (!response.ok) throw new Error(String(response.status))
      this.pick(await response.json())
    } catch {
      this.status("We couldn't find a city near you. Type your city instead.", "error")
    } finally {
      this.locateTarget.disabled = false
    }
  }

  // Why the browser couldn't share a location, and what to do about it.
  locationError(error) {
    if (error?.code === 1) {
      return "Location is blocked for Brethreign. Allow it in your browser (the icon beside the web address → Location → Allow), then try again. Or just type your city."
    }
    if (error?.code === 2) {
      return "Your device couldn't find where you are. Check that Location Services is on, or type your city."
    }
    return "Finding your location took too long. Try again, or type your city."
  }

  status(text, tone = "") {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.classList.toggle("is-error", tone === "error")
    this.statusTarget.classList.toggle("is-ok", tone === "ok")
  }
}
