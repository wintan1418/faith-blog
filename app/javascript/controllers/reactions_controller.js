import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown"]

  connect() {
    // Close dropdown when clicking outside
    this.boundCloseDropdown = this.closeDropdown.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseDropdown)
  }

  showDropdown(event) {
    event.preventDefault()
    event.stopPropagation()
    
    if (this.hasDropdownTarget) {
      // Toggle visibility
      const isHidden = this.dropdownTarget.classList.contains("hidden")
      
      if (isHidden) {
        this.dropdownTarget.classList.remove("hidden")
        // Close on outside click
        setTimeout(() => {
          document.addEventListener("click", this.boundCloseDropdown)
        }, 100)
      } else {
        this.hideDropdown()
      }
    }
  }

  hideDropdown() {
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.add("hidden")
      document.removeEventListener("click", this.boundCloseDropdown)
    }
  }

  closeDropdown(event) {
    if (!this.element.contains(event.target) && this.hasDropdownTarget) {
      this.hideDropdown()
    }
  }
}
