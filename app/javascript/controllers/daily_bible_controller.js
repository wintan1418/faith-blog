import { Controller } from "@hotwired/stimulus"

// The Daily Bible card on the feed: opens the settings sheet and the
// "Pray it" sheet (straight away after "I've read it"), and tells the server
// the browser's time zone so "today" and the reminder are the member's own.
export default class extends Controller {
  static targets = ["sheet", "prayerSheet", "zoneField"]
  static values = { zone: String, zoneUrl: String, openPrayer: Boolean, openSheet: Boolean }

  connect() {
    const zone = this.browserZone()
    if (this.hasZoneFieldTarget && zone) this.zoneFieldTarget.value = zone
    if (zone && zone !== this.zoneValue && this.zoneUrlValue) this.sendZone(zone)
    if (this.openPrayerValue && this.hasPrayerSheetTarget) this.show(this.prayerSheetTarget)
    // "Start your daily reading" from a shared reading card: the plan picker.
    if (this.openSheetValue && this.hasSheetTarget) {
      this.openSheetValue = false
      this.element.scrollIntoView({ block: "start" })
      this.show(this.sheetTarget)
    }
  }

  openSheet(event) {
    event?.preventDefault()
    this.show(this.sheetTarget)
  }

  closeSheet(event) {
    event?.preventDefault()
    this.hide(this.sheetTarget)
  }

  openPrayer(event) {
    event?.preventDefault()
    if (this.hasPrayerSheetTarget) this.show(this.prayerSheetTarget)
  }

  closePrayer(event) {
    event?.preventDefault()
    if (this.hasPrayerSheetTarget) this.hide(this.prayerSheetTarget)
  }

  // A tap on the dimmed backdrop (the dialog itself, outside its body) closes it.
  backdrop(event) {
    if (event.target.tagName === "DIALOG") this.hide(event.target)
  }

  show(dialog) {
    if (dialog.open) return
    if (typeof dialog.showModal === "function") dialog.showModal()
    else dialog.setAttribute("open", "")
  }

  hide(dialog) {
    if (dialog.open) dialog.close()
  }

  browserZone() {
    try { return Intl.DateTimeFormat().resolvedOptions().timeZone || "" } catch { return "" }
  }

  sendZone(zone) {
    const token = document.querySelector("meta[name=csrf-token]")?.content || ""
    const body = new FormData()
    body.set("time_zone", zone)
    fetch(this.zoneUrlValue, { method: "POST", body, credentials: "same-origin", headers: { "X-CSRF-Token": token } })
      .then(() => { this.zoneValue = zone })
      .catch(() => {})
  }
}
