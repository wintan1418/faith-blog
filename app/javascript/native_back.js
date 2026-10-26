// Android's Back button in the app asks the page to close whatever is open on top
// (composer, Bible drawer, photo viewer, any dialog) before leaving the screen.
// Returns true when something was closed, so the app knows Back was used up.
window.nativeCloseOverlay = () => {
  const pressEscape = () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))

  // Only report "closed" if something was really open and really closed; a leftover
  // body class used to swallow every Back press.
  const openOverlay = () => document.querySelector(
    ".fc-lightbox, .fc-bible-drawer:not(.hidden), [data-history-arena-target='drawer']:not(.hidden)"
  )
  if (openOverlay()) {
    pressEscape()
    if (!openOverlay()) return true
    // Escape wasn't heard (a stale copy from a page snapshot): close it by hand.
    document.querySelectorAll(".fc-lightbox").forEach((el) => el.remove())
    document.querySelectorAll(".fc-bible-drawer, [data-history-arena-target='drawer']").forEach((el) => el.classList.add("hidden"))
    document.body.classList.remove("fc-lightbox-open", "fc-bible-open")
    return true
  }
  document.body.classList.remove("fc-lightbox-open", "fc-bible-open")

  const dialogs = [...document.querySelectorAll("dialog[open]")]
  const top = dialogs[dialogs.length - 1]
  if (top) {
    if (typeof top.close === "function") top.close()
    else top.removeAttribute("open")
    return true
  }

  return false
}
