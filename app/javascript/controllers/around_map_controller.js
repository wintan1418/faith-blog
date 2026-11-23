import { Controller } from "@hotwired/stimulus"

// City-level map for Breathers around you: one dot per city with how many
// breathers live there, never a dot per person. Leaflet (pinned version from a
// CDN) loads only when a map is on screen. Tiles © OpenStreetMap contributors
// (credited in the card's footer).
const LEAFLET = "https://unpkg.com/leaflet@1.9.4/dist/"
const JS_SRI = "sha384-cxOPjt7s7Iz04uaHJceBmS+qpjv2JkIHNVcuOrM+YHwZOmJGBXI00mdUXEq65HTH"
const CSS_SRI = "sha384-sHL9NAb7lN7rfvG5lfHpm643Xkcjzp4jFvuavGOndn6pjVqS6ny56CAt3nsEVT4H"

let leaflet
function loadLeaflet() {
  if (window.L) return Promise.resolve(window.L)
  return (leaflet ||= new Promise((resolve, reject) => {
    const css = document.createElement("link")
    Object.assign(css, { rel: "stylesheet", href: `${LEAFLET}leaflet.css`, integrity: CSS_SRI, crossOrigin: "" })
    document.head.append(css)
    const script = document.createElement("script")
    Object.assign(script, { src: `${LEAFLET}leaflet.js`, integrity: JS_SRI, crossOrigin: "", async: true })
    script.onload = () => resolve(window.L)
    script.onerror = () => { leaflet = null; reject(new Error("Leaflet failed to load")) }
    document.head.append(script)
  }))
}

const escape = (text) => String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))

export default class extends Controller {
  static targets = ["canvas", "chip", "status"]
  static values = { dots: Array }

  connect() {
    this.area = "near"
    // Phones show the map at the top, desktops on the right: only draw the one on screen.
    this.media = window.matchMedia("(min-width: 1024px)")
    this.onMedia = () => this.drawIfVisible()
    this.media.addEventListener("change", this.onMedia)
    this.drawIfVisible()
  }

  disconnect() {
    this.media?.removeEventListener("change", this.onMedia)
    this.map?.remove()
    this.map = null
  }

  async drawIfVisible() {
    if (this.map) return this.map.invalidateSize()
    if (!this.element.getClientRects().length) return

    this.statusTarget.textContent = "Loading map…"
    try {
      const L = await loadLeaflet()
      if (this.map || !this.element.isConnected) return
      this.draw(L)
      this.statusTarget.textContent = ""
    } catch {
      this.statusTarget.textContent = "The map couldn't load. Check your connection."
    }
  }

  draw(L) {
    this.L = L
    this.markers = []
    this.map = L.map(this.canvasTarget, { scrollWheelZoom: false, attributionControl: false, zoomControl: false, worldCopyJump: true })
    L.control.zoom({ position: "topright" }).addTo(this.map)
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 12, minZoom: 2 }).addTo(this.map)

    this.dotsValue.forEach((dot) => {
      const size = dot.mine ? 46 : Math.min(24 + Math.round(Math.log2(dot.count + 1) * 5), 44)
      const tone = dot.mine ? "is-mine" : dot.near ? "is-near" : "is-far"
      const label = dot.mine ? `${dot.name} · you` : dot.name
      const html = `<span class="am-dot ${tone}" style="width:${size}px;height:${size}px">` +
        (dot.mine ? '<span class="am-ping" aria-hidden="true"></span>' : "") +
        `<span class="am-count">${dot.count || ""}</span></span><span class="am-label">${escape(label)}</span>`
      const icon = L.divIcon({ className: "am-wrap", html, iconSize: [size, size], iconAnchor: [size / 2, size / 2] })
      const people = dot.count === 1 ? "1 breather" : `${dot.count} breathers`
      const where = dot.distance ? `${label} (${dot.distance})` : label
      const marker = L.marker([dot.lat, dot.lng], { icon, title: `${where}: ${people}`, keyboard: true, riseOnHover: true,
                                                    zIndexOffset: dot.mine ? 1000 : dot.count })
      marker.addTo(this.map)
      this.markers.push({ marker, dot })
    })
    this.map.on("zoomend moveend", () => this.declutter())
    this.fit()
  }

  // City names can't overlap: your city first, then the busiest, the rest hide until you zoom in.
  declutter() {
    const placed = []
    const order = [...this.markers].sort((a, b) => (b.dot.mine - a.dot.mine) || (b.dot.count - a.dot.count))
    order.forEach(({ marker }) => {
      const label = marker.getElement()?.querySelector(".am-label")
      if (!label) return
      label.classList.remove("is-hidden")
      const box = label.getBoundingClientRect()
      const clash = placed.some((p) => box.left < p.right && box.right > p.left && box.top < p.bottom && box.bottom > p.top)
      if (clash) label.classList.add("is-hidden")
      else placed.push(box)
    })
  }

  setArea(event) {
    this.area = event.currentTarget.dataset.scope
    this.chipTargets.forEach((chip) => {
      const on = chip.dataset.scope === this.area
      chip.classList.toggle("is-active", on)
      chip.setAttribute("aria-pressed", String(on))
    })
    this.fit()
  }

  fit() {
    if (!this.map) return
    const dots = this.dotsValue.filter((d) => this.area === "world" || (this.area === "near" ? d.near : d.country))
    const points = dots.map((d) => [d.lat, d.lng])
    if (this.area === "world" && points.length < 2) return this.map.setView(points[0] || [20, 0], 2)
    if (points.length > 1) this.map.fitBounds(points, { padding: [48, 48], maxZoom: this.area === "near" ? 10 : 7 })
    else if (points.length === 1) this.map.setView(points[0], this.area === "near" ? 9 : 5)
  }
}
