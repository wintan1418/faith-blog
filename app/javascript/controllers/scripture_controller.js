import { Controller } from "@hotwired/stimulus"

// Auto-link Bible references inside an element. Wrap matches in
// .scripture-ref spans with a data attribute holding the reference.
// On hover, fetch /scripture/lookup?reference=... once and show a
// tooltip with the verse text.
export default class extends Controller {
  static REGEX = new RegExp(
    String.raw`\b((?:[1-3]\s?)?(?:Gen(?:esis)?|Exo(?:dus)?|Lev(?:iticus)?|Num(?:bers)?|Deut(?:eronomy)?|Josh(?:ua)?|Judg(?:es)?|Ruth|Sam(?:uel)?|Kings|Chron(?:icles)?|Ezra|Neh(?:emiah)?|Esth(?:er)?|Job|Ps(?:alm[s]?)?|Prov(?:erbs)?|Eccl(?:esiastes)?|Song|Isa(?:iah)?|Jer(?:emiah)?|Lam(?:entations)?|Ezek(?:iel)?|Dan(?:iel)?|Hos(?:ea)?|Joel|Amos|Obad(?:iah)?|Jon(?:ah)?|Mic(?:ah)?|Nah(?:um)?|Hab(?:akkuk)?|Zeph(?:aniah)?|Hag(?:gai)?|Zech(?:ariah)?|Mal(?:achi)?|Matt(?:hew)?|Mark|Luke|John|Acts|Rom(?:ans)?|Cor(?:inthians)?|Gal(?:atians)?|Eph(?:esians)?|Phil(?:ippians)?|Col(?:ossians)?|Thess(?:alonians)?|Tim(?:othy)?|Tit(?:us)?|Phil(?:emon)?|Heb(?:rews)?|Jas|James|Pet(?:er)?|Jude|Rev(?:elation)?)\s+\d{1,3}(?::\d{1,3}(?:[-–]\d{1,3})?)?)\b`,
    "gi"
  )

  connect() {
    this.cache = new Map()
    this.linkifyAll(this.element)
  }

  linkifyAll(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => {
        if (!node.nodeValue || node.nodeValue.length < 5) return NodeFilter.FILTER_REJECT
        if (node.parentElement?.closest("a, .scripture-ref, .mention-link")) return NodeFilter.FILTER_REJECT
        return this.constructor.REGEX.test(node.nodeValue)
          ? NodeFilter.FILTER_ACCEPT
          : NodeFilter.FILTER_REJECT
      }
    })

    const nodes = []
    let n
    while ((n = walker.nextNode())) nodes.push(n)

    nodes.forEach(node => this.wrap(node))
  }

  wrap(textNode) {
    const text = textNode.nodeValue
    const frag = document.createDocumentFragment()
    let lastIndex = 0
    this.constructor.REGEX.lastIndex = 0

    let match
    while ((match = this.constructor.REGEX.exec(text)) !== null) {
      const start = match.index
      const end = start + match[0].length

      if (start > lastIndex) {
        frag.appendChild(document.createTextNode(text.slice(lastIndex, start)))
      }

      const span = document.createElement("span")
      span.className = "scripture-ref"
      span.dataset.reference = match[0]
      span.textContent = match[0]
      span.addEventListener("mouseenter", (e) => this.show(e.currentTarget))
      span.addEventListener("focus", (e) => this.show(e.currentTarget), true)
      span.addEventListener("mouseleave", () => this.hide())
      span.tabIndex = 0
      frag.appendChild(span)

      lastIndex = end
    }

    if (lastIndex < text.length) {
      frag.appendChild(document.createTextNode(text.slice(lastIndex)))
    }

    textNode.parentNode.replaceChild(frag, textNode)
  }

  async show(span) {
    const ref = span.dataset.reference
    if (!ref) return

    let tip = this.tip
    if (!tip) {
      tip = document.createElement("div")
      tip.className = "scripture-tip"
      document.body.appendChild(tip)
      this.tip = tip
    }

    const rect = span.getBoundingClientRect()
    tip.style.position = "fixed"
    tip.style.top = `${rect.bottom + 6}px`
    tip.style.left = `${Math.max(8, rect.left)}px`
    tip.style.maxWidth = "min(360px, calc(100vw - 16px))"
    tip.classList.add("is-loading")
    tip.classList.remove("hidden")
    tip.innerHTML = `<p class="scripture-tip-loading">Loading ${ref}…</p>`

    let payload = this.cache.get(ref.toLowerCase())
    if (!payload) {
      try {
        const response = await fetch(`/scripture/lookup?reference=${encodeURIComponent(ref)}`, {
          headers: { "Accept": "application/json" }
        })
        if (response.ok) payload = await response.json()
      } catch { /* ignore */ }
      if (payload) this.cache.set(ref.toLowerCase(), payload)
    }

    tip.classList.remove("is-loading")
    if (payload && payload.text) {
      tip.innerHTML = `
        <p class="scripture-tip-ref">${payload.reference || ref}</p>
        <p class="scripture-tip-text">${this.escape(payload.text)}</p>
        <p class="scripture-tip-translation">${payload.translation || "KJV"}</p>
      `
    } else {
      tip.innerHTML = `<p class="scripture-tip-loading">Couldn't load ${ref}.</p>`
    }
  }

  hide() {
    if (this.tip) this.tip.classList.add("hidden")
  }

  disconnect() {
    if (this.tip) {
      this.tip.remove()
      this.tip = null
    }
  }

  escape(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  }
}
