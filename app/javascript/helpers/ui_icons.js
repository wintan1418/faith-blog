// The same outline icons as IconHelper (app/helpers/icon_helper.rb), for
// labels that Stimulus controllers write at runtime.
const PATHS = {
  check: "M20 6 9 17l-5-5",
  x: "M18 6 6 18M6 6l12 12",
  copy: "M10 8h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H10a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2zM4 16a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2",
  sparkles: "M9.9 14.1 12 21l2.1-6.9L21 12l-6.9-2.1L12 3 9.9 9.9 3 12z",
  bell: "M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.94 1.94 0 0 0 3.4 0",
  belloff: "M8.7 3A6 6 0 0 1 18 8a21.3 21.3 0 0 0 .6 5M17 17H3s3-2 3-9a4.7 4.7 0 0 1 .3-1.7M10.3 21a1.94 1.94 0 0 0 3.4 0M2 2l20 20",
  ban: "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM4.9 4.9l14.2 14.2",
  volume: "M11 5 6 9H2v6h4l5 4zM15.5 8.5a5 5 0 0 1 0 7M19 5a10 10 0 0 1 0 14",
  volumeoff: "M11 5 6 9H2v6h4l5 4zM22 9l-6 6M16 9l6 6",
  dove: "M16 7h.01M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.3-2.3L2 20M20 7l2 .5-2 .5M10 18v3M14 17.8V21M7 18a6 6 0 0 0 3.8-10.6",
  chat: "M7.9 20A9 9 0 1 0 4 16.1L2 22z",
  alert: "M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0zM12 9v4M12 17h.01",
  bookopen: "M2 4h6a4 4 0 0 1 4 4v13a3 3 0 0 0-3-3H2zM22 4h-6a4 4 0 0 0-4 4v13a3 3 0 0 1 3-3h7z"
}

export function iconSvg(name, cls = "h-4 w-4") {
  const d = PATHS[name]
  if (!d) return ""
  return `<svg xmlns="http://www.w3.org/2000/svg" class="${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><path d="${d}"/></svg>`
}

const escapeHtml = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))

// Drops a leading emoji from older label strings ("🔔 Sounds on" → "Sounds on").
export const stripLeadingEmoji = (s) => String(s || "").replace(/^[\p{Extended_Pictographic}️‍\s]+/u, "")

// An icon followed by its text label, as HTML.
export function iconLabel(name, text, cls = "h-4 w-4") {
  return `${iconSvg(name, cls)}<span>${escapeHtml(stripLeadingEmoji(text))}</span>`
}
