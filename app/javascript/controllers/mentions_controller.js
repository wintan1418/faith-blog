import { Controller } from "@hotwired/stimulus"
import Tribute from "tributejs"

export default class extends Controller {
  connect() {
    this.initializeTribute()
  }

  disconnect() {
    if (this.tribute) this.tribute.detach(this.element)
  }

  initializeTribute() {
    // If we're inside a <dialog>, the dropdown has to live inside the dialog
    // too — otherwise it ends up below the modal's top-layer backdrop.
    const dialog = this.element.closest("dialog")
    const menuContainer = dialog || document.body

    this.tribute = new Tribute({
      allowSpaces: false,
      autocompleteMode: false,
      trigger: "@",
      menuContainer: menuContainer,
      positionMenu: true,
      values: (text, cb) => {
        this.fetchUsers(text, cb)
      },
      lookup: "username",
      fillAttr: "username",
      noMatchTemplate: () => '<div class="mention-empty">No matching people</div>',
      menuItemTemplate: function (item) {
        if (item.original.broadcast) {
          const cls = item.original.platform ? "mention-broadcast-icon is-platform" : "mention-broadcast-icon"
          return `
            <div class="mention-option mention-option-broadcast">
              <div class="${cls}">@</div>
              <div class="mention-copy">
                <span>@${item.original.username}</span>
                <small>${item.original.name || ""}</small>
              </div>
            </div>
          `
        }
        return `
          <div class="mention-option">
            ${item.original.avatar_url
              ? `<img src="${item.original.avatar_url}" class="mention-avatar">`
              : `<div class="mention-avatar mention-avatar-fallback">${item.original.username.charAt(0).toUpperCase()}</div>`
            }
            <div class="mention-copy">
              <span>@${item.original.username}</span>
              <small>${item.original.name || ""}</small>
            </div>
          </div>
        `
      },
      selectTemplate: function(item) {
        if (!item) return null
        return `@${item.original.username} `
      }
    })

    this.tribute.attach(this.element)
  }

  fetchUsers(text, cb) {
    fetch(`/mentions?query=${encodeURIComponent(text)}`, {
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(users => cb(users))
    .catch(error => {
      console.error("Error fetching mentions:", error)
      cb([])
    })
  }
}
