// Heavy libraries load on demand instead of with every page (they were over half
// of the JavaScript). Each loader runs once; later calls reuse the same promise.
const once = (load) => { let promise; return () => (promise ||= load()) }

export const loadEditor = once(() => import("trix").then(() => import("@rails/actiontext")))
export const loadEmojiPicker = once(() => import("emoji-picker-element"))
export const loadTribute = once(() => import("tributejs").then((m) => m.default))
export const loadChess = once(() => import("chess.js").then((m) => m.Chess))

const whenIdle = (fn) => (window.requestIdleCallback ? window.requestIdleCallback(fn, { timeout: 2500 }) : setTimeout(fn, 1200))

// Editors you can see right away (e.g. the new-post page) load now; ones hidden in
// the composer or reply boxes load quietly once the page is idle.
function preload() {
  const editors = [...document.querySelectorAll("trix-editor")]
  if (editors.some((e) => e.offsetParent !== null && !e.closest("dialog:not([open])"))) loadEditor()
  else if (editors.length) whenIdle(loadEditor)

  if (document.querySelector("emoji-picker")) whenIdle(loadEmojiPicker)
}

document.addEventListener("turbo:load", preload)
