import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["previews"]

  previewImages(event) {
    const files = Array.from(event.target.files)
    const previewContainer = this.previewsTarget
    
    // Clear previous previews
    previewContainer.innerHTML = ""
    previewContainer.classList.remove("hidden")
    
    // Limit to 5 images
    const limitedFiles = files.slice(0, 5)
    
    limitedFiles.forEach((file, index) => {
      if (file.type.startsWith('image/')) {
        const reader = new FileReader()
        reader.onload = (e) => {
          const div = document.createElement('div')
          div.className = 'relative group'
          
          const img = document.createElement('img')
          img.src = e.target.result
          img.className = 'w-full h-24 object-cover rounded-lg'
          
          const removeBtn = document.createElement('button')
          removeBtn.type = 'button'
          removeBtn.className = 'absolute top-1 right-1 w-6 h-6 bg-red-500 text-white rounded-full opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center text-xs'
          removeBtn.innerHTML = '×'
          removeBtn.onclick = () => {
            div.remove()
            // Remove from file input
            const dt = new DataTransfer()
            const input = event.target
            Array.from(input.files).forEach((f, i) => {
              if (i !== index) dt.items.add(f)
            })
            input.files = dt.files
            if (previewContainer.children.length === 0) {
              previewContainer.classList.add("hidden")
            }
          }
          
          div.appendChild(img)
          div.appendChild(removeBtn)
          previewContainer.appendChild(div)
        }
        reader.readAsDataURL(file)
      }
    })
    
    // Warn if more than 5
    if (files.length > 5) {
      alert("You can only upload up to 5 images. Only the first 5 will be used.")
    }
  }
}
