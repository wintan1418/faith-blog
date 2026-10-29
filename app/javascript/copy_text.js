// Copies text and resolves true when it worked. Works in the Android app
// (its native bridge), in browsers (Clipboard API), and in older WebViews
// that refuse the Clipboard API (hidden textarea + execCommand).
export async function copyText(text) {
  if (!text) return false
  const native = window.BrethreignNative
  if (native && typeof native.copy === "function") {
    try { native.copy(text); return true } catch { /* fall through */ }
  }
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    const field = Object.assign(document.createElement("textarea"), { value: text })
    field.setAttribute("readonly", "")
    field.style.cssText = "position:fixed;top:0;left:0;opacity:0"
    document.body.appendChild(field)
    field.select()
    field.setSelectionRange(0, text.length)
    let ok = false
    try { ok = document.execCommand("copy") } catch { ok = false }
    field.remove()
    return ok
  }
}
