// Android's Back button in the app asks the page to close whatever is open on top
// (composer, Bible drawer, photo viewer, any dialog) before leaving the screen.
// Returns true when something was closed, so the app knows Back was used up.
window.nativeCloseOverlay = () => {
  const pressEscape = () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))

  if (document.body.classList.contains("fc-lightbox-open") || document.body.classList.contains("fc-bible-open")) {
    pressEscape()
    return true
  }

  const dialogs = [...document.querySelectorAll("dialog[open]")]
  const top = dialogs[dialogs.length - 1]
  if (top) {
    if (typeof top.close === "function") top.close()
    else top.removeAttribute("open")
    return true
  }

  return false
}
