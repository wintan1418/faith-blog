// Saves a closed card on the account so it stays closed on every device.
export function rememberDismissal(key) {
  if (!key) return
  const token = document.querySelector("meta[name=csrf-token]")?.content || ""
  const body = new FormData()
  body.set("key", key)
  fetch("/dismissals", { method: "POST", body, credentials: "same-origin", keepalive: true, headers: { "X-CSRF-Token": token } })
    .catch(() => {})
}
