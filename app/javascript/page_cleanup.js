// Turbo (and the apps) keep a snapshot of each page and show it again on Back.
// Anything left open in that snapshot (photo viewer, composer, a pop-up dialog,
// the Bible drawer) used to come back stuck: the page couldn't scroll and nothing
// could close it. Close everything before a snapshot is taken, and clear any
// leftover lock when a page shows.

function closeOverlays() {
  document.querySelectorAll("dialog[open]").forEach((d) => {
    if (typeof d.close === "function") d.close()
    else d.removeAttribute("open")
  })
  document.querySelectorAll(".fc-lightbox, #fc-splash").forEach((el) => el.remove())
  document.querySelectorAll(".fc-bible-drawer:not(.hidden), [data-bible-drawer-target='panel']:not(.hidden)")
    .forEach((el) => { el.classList.add("hidden"); el.setAttribute("aria-hidden", "true") })
  document.querySelectorAll("[data-history-arena-target='drawer']:not(.hidden)").forEach((el) => el.classList.add("hidden"))
  document.querySelectorAll(".msg-actions.is-open, .message-actions.is-open").forEach((el) => el.classList.remove("is-open"))
  clearLocks()
}

// Body classes that lock scrolling, removed when nothing they belong to is open.
function clearLocks() {
  const body = document.body
  if (!body) return
  if (!document.querySelector(".fc-lightbox")) body.classList.remove("fc-lightbox-open")
  if (!document.querySelector(".fc-bible-drawer:not(.hidden), [data-bible-drawer-target='panel']:not(.hidden)")) body.classList.remove("fc-bible-open")
  document.documentElement.style.removeProperty("overflow")
  body.style.removeProperty("overflow")
}

document.addEventListener("turbo:before-cache", closeOverlays)
document.addEventListener("turbo:load", clearLocks)
window.addEventListener("pageshow", clearLocks)
