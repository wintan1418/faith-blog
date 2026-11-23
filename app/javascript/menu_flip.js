// Menus that open upward slide under the sticky top bar when their button is
// near the top of the screen. Open those downward instead.
const TOP_BAR = 72

export function flipIfNoRoomAbove(menu) {
  menu.classList.remove("opens-down")
  if (menu.getBoundingClientRect().top < TOP_BAR) menu.classList.add("opens-down")
  keepInsideScreen(menu)
}

// Menus are anchored to their button's right edge. When the button sits near
// the left of a phone screen (e.g. Share on a post's own page) the menu ran
// off the left edge. Nudge it sideways so it stays fully visible.
const EDGE = 8
export function keepInsideScreen(menu) {
  menu.style.translate = ""
  const box = menu.getBoundingClientRect()
  const width = document.documentElement.clientWidth
  let shift = 0
  if (box.left < EDGE) shift = EDGE - box.left
  else if (box.right > width - EDGE) shift = (width - EDGE) - box.right
  if (shift) menu.style.translate = `${Math.round(shift)}px 0`
}
