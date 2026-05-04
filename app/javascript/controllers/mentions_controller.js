import { Controller } from "@hotwired/stimulus"
import Tribute from "tributejs"

export default class extends Controller {
  connect() {
    console.log("🔔 MentionsController connected!", this.element)
    this.initializeTribute()
  }

  initializeTribute() {
    console.log("🛠️ Initializing Tribute.js...")
    this.tribute = new Tribute({
      allowSpaces: false,
      trigger: "@",
      values: (text, cb) => {
        this.fetchUsers(text, cb)
      },
      lookup: "username",
      fillAttr: "username",
      menuItemTemplate: function (item) {
        return `
          <div class="flex items-center gap-2 p-2">
            ${item.original.avatar_url 
              ? `<img src="${item.original.avatar_url}" class="w-6 h-6 rounded-full object-cover">` 
              : `<div class="w-6 h-6 rounded-full bg-gray-200 flex items-center justify-center text-xs font-bold text-gray-500">${item.original.username.charAt(0).toUpperCase()}</div>`
            }
            <div class="flex flex-col">
              <span class="font-medium text-sm text-gray-900">${item.original.username}</span>
              <span class="text-xs text-gray-500">${item.original.name || ""}</span>
            </div>
          </div>
        `
      },
      selectTemplate: function(item) {
        return `@${item.original.username}`;
      }
    })

    this.tribute.attach(this.element)
  }

  fetchUsers(text, cb) {
    console.log(`🔍 Fetching users for query: "${text}"`)
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
