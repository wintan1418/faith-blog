// Files in chats download from /inbox/…/files/… under their original name. App builds
// that save those downloads themselves add "NativeDownloads" to their user agent; older
// builds can't open that link (they show an error screen), so for them the tap goes to
// the old file-store link instead (data-legacy-href), which opens the phone's browser.
const olderApp = () =>
  document.body?.classList.contains("hotwire-native") && !navigator.userAgent.includes("NativeDownloads")

document.addEventListener("click", (event) => {
  const link = event.target.closest?.("a[data-legacy-href]")
  if (link && link.dataset.legacyHref && olderApp()) link.href = link.dataset.legacyHref
}, true)
