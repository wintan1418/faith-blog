import { Controller } from "@hotwired/stimulus"

// Inline edit a single message bubble.
// Click the pencil → replaces the body with a small editor.
// Save → PATCH /conversations/:id/messages/:id, response replaces the bubble.
// Cancel → restore original.
export default class extends Controller {
  start(event) {
    event.preventDefault()
    const id = event.params?.messageId || event.currentTarget.closest("[id^='message_']")?.id?.replace("message_", "")
    if (!id) return

    const row = event.currentTarget.closest(".message-row")
    if (!row) return
    const body = row.querySelector(".message-body")
    if (!body) return

    const original = body.innerHTML
    const text = body.innerText.trim()
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content || ""
    const conversationId = window.location.pathname.match(/\/inbox\/(\d+)/)?.[1]
    if (!conversationId) return

    body.innerHTML = `
      <div class="message-edit">
        <textarea class="message-edit-input" rows="3">${text.replace(/</g, "&lt;")}</textarea>
        <div class="message-edit-actions">
          <button type="button" class="fc-btn message-edit-cancel">Cancel</button>
          <button type="button" class="fc-btn fc-btn-primary message-edit-save">Save</button>
        </div>
      </div>
    `

    const textarea = body.querySelector("textarea")
    textarea.focus()
    textarea.setSelectionRange(textarea.value.length, textarea.value.length)

    body.querySelector(".message-edit-cancel").addEventListener("click", () => {
      body.innerHTML = original
    })

    body.querySelector(".message-edit-save").addEventListener("click", async () => {
      const newBody = textarea.value.trim()
      if (newBody.length === 0) {
        body.innerHTML = original
        return
      }

      const fd = new FormData()
      fd.set("authenticity_token", csrf)
      fd.set("message[body]", newBody)

      try {
        const response = await fetch(`/inbox/${conversationId}/messages/${id}`, {
          method: "PATCH",
          body: fd,
          headers: { "Accept": "text/vnd.turbo-stream.html, text/html" },
          credentials: "same-origin"
        })
        if (response.ok) {
          const text = await response.text()
          if (response.headers.get("content-type")?.includes("turbo-stream") && window.Turbo) {
            window.Turbo.renderStreamMessage(text)
          } else {
            window.location.reload()
          }
        } else {
          body.innerHTML = original
        }
      } catch {
        body.innerHTML = original
      }
    })
  }
}
