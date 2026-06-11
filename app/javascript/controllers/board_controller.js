import { Controller } from "@hotwired/stimulus"

// Board extras: grid toggle and preview-to-full image swap.
export default class extends Controller {
  static targets = ["grid", "image"]
  static values = { fullSrc: String }

  connect() {
    if (this.hasImageTarget && this.fullSrcValue &&
        this.imageTarget.src !== this.fullSrcValue) {
      const full = new Image()
      full.onload = () => { this.imageTarget.src = this.fullSrcValue }
      full.src = this.fullSrcValue
    }
  }

  toggleGrid() {
    this.gridTargets.forEach(grid => grid.hidden = !grid.hidden)
  }
}
