// Menus that open upward slide under the sticky top bar when their button is
// near the top of the screen. Open those downward instead.
const TOP_BAR = 72

export function flipIfNoRoomAbove(menu) {
  menu.classList.remove("opens-down")
  if (menu.getBoundingClientRect().top < TOP_BAR) menu.classList.add("opens-down")
}
