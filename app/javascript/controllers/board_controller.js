import { Controller } from "@hotwired/stimulus"

// Board extras: grid/numbering toggles and preview-to-full image swap.
export default class extends Controller {
  static targets = ["gridLines", "numbering", "image"]

  connect() {
    // Swap each board preview for its full-resolution image once loaded
    this.imageTargets.forEach(img => {
      const fullSrc = img.dataset.fullSrc
      if (!fullSrc || img.src === fullSrc) return
      const full = new Image()
      full.onload = () => { img.src = fullSrc }
      full.src = fullSrc
    })
  }

  // SVG elements ignore the hidden property; toggle the attribute (mirrored
  // to display:none via CSS).
  toggleGrid() {
    this.gridLinesTargets.forEach(g => g.toggleAttribute("hidden"))
  }

  toggleNumbering() {
    this.numberingTargets.forEach(g => g.toggleAttribute("hidden"))
  }
}
