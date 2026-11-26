import { Controller } from "@hotwired/stimulus"

// "Join to continue" for signed-out web visitors (attached on <body> only for
// them; never in the apps, never for members). They can read the page they
// landed on, but any further click on a link or button inside the site opens
// a dialog inviting them to create an account or sign in.
//
// One capture-phase listener instead of editing every link. What stays open:
// sign up / sign in / password pages, Google sign-in, the legal pages, the
// welcome page "/" and its app waitlist, other websites, same-page #anchors, and anything inside an
// element marked data-guest-gate-allow (the dialog itself, cookie choice,
// flash messages, theme toggle). The server still requires sign-in for every
// action that needs it; this is the friendly front for that.

const OPEN_PATHS = [
  /^\/users\/(sign_in|sign_up|password|confirmation|unlock|auth)(\/|$)/, // Devise + Google
  /^\/users\/?$/,                                                       // sign-up form submit
  /^\/auth\//,                                                          // app sign-in hand-offs
  /^\/(privacy|terms|child-safety|about|guidelines|contact)\/?$/,
  /^\/waitlist(\/leave\/[^/]+)?\/?$/,                                                   // "Get the app" on the welcome page
  /^\/scripture(\/|$)/                                                   // the public Bible pages (books, chapters, verses)
]

const ENTRY_PATHS = /^\/users\/(sign_in|sign_up)\/?$/
const ENTRY_CHROME = ".fc-topbar, .fc-bottom-nav, .auth, .welcome, .guest-more"

const CLICKABLE = [
  "a[href]", "button", "summary", "[role=button]", "[role=link]",
  "input[type=submit]", "input[type=button]", "input[type=image]",
  "[data-action*='click->']"
].join(",")

export function openUrl(href, base = window.location.href) {
  let url
  try { url = new URL(href, base) } catch (e) { return true }
  if (url.protocol !== "http:" && url.protocol !== "https:") return true // mailto:, tel:
  if (url.origin !== new URL(base).origin) return true                   // other websites
  if (url.pathname === "/" && !url.search) return true                    // the welcome page
  return OPEN_PATHS.some((re) => re.test(url.pathname))
}

export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.onClick = this.onClick.bind(this)
    this.onSubmit = this.onSubmit.bind(this)
    document.addEventListener("click", this.onClick, true)
    document.addEventListener("submit", this.onSubmit, true)
  }

  disconnect() {
    document.removeEventListener("click", this.onClick, true)
    document.removeEventListener("submit", this.onSubmit, true)
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  onClick(event) {
    if (!(event.target instanceof Element)) return
    const el = event.target.closest(CLICKABLE)
    if (!el || this.allowed(el)) return
    this.block(event, el)
  }

  // Enter in a search box submits without a click.
  onSubmit(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement) || form.closest("[data-guest-gate-allow]")) return
    if (openUrl(form.getAttribute("action") || window.location.href)) return
    this.block(event, event.submitter || form)
  }

  allowed(el) {
    if (el.closest("[data-guest-gate-allow]")) return true
    if (el.matches("a[href]")) {
      const href = el.getAttribute("href")
      if (href.startsWith("#")) return true // same-page anchor
      if (!openUrl(el.href)) return false
      // "Sign in" / "Join" links in the top bar, bottom bar and sign-in pages go
      // straight there. The same links inside the page (like, save, the composer
      // prompt) open the dialog instead, which offers both.
      if (ENTRY_PATHS.test(new URL(el.href).pathname)) return !!el.closest(ENTRY_CHROME)
      return true
    }
    // A button inside a form that goes somewhere open (sign-in submit, show password, Google).
    const form = el.form || el.closest("form")
    if (form) return openUrl(el.getAttribute("formaction") || form.getAttribute("action") || window.location.href)
    return false
  }

  block(event, el) {
    event.preventDefault()
    event.stopImmediatePropagation()
    this.open(el)
  }

  open(from) {
    if (!this.hasDialogTarget) return
    this.returnFocus = from instanceof HTMLElement ? from : document.activeElement
    this.pointAuthLinksAt(this.destination(from))
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  // Where the visitor was heading: the tapped link's page on this site, or else
  // the page they're on (a like or comment button). The server only keeps safe paths.
  destination(from) {
    const here = window.location.pathname + window.location.search
    const link = from instanceof Element ? from.closest("a[href]") : null
    if (!link) return here
    try {
      const url = new URL(link.href, window.location.href)
      // Like / save / comment buttons for guests point at sign-up: return to this page instead.
      if (url.origin !== window.location.origin || /^\/(users|auth)(\/|$)/.test(url.pathname)) return here
      return url.pathname + url.search
    } catch (e) { return here }
  }

  pointAuthLinksAt(path) {
    this.dialogTarget.querySelectorAll("a[data-guest-gate-auth]").forEach((a) => {
      const url = new URL(a.getAttribute("href"), window.location.href)
      url.searchParams.set("return_to", path)
      a.setAttribute("href", url.pathname + url.search)
    })
  }

  close(event) {
    event?.preventDefault()
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  // Click on the dimmed backdrop (the dialog element itself, outside the card).
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  closed() {
    this.returnFocus?.focus?.({ preventScroll: true })
    this.returnFocus = null
  }
}
