import { Controller } from "@hotwired/stimulus"

// Board extras: grid/numbering toggles and preview-to-full image swap.
export default class extends Controller {
  static targets = ["gridLines", "numbering", "image"]
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
    this.gridLinesTargets.forEach(g => g.hidden = !g.hidden)
  }

  toggleNumbering() {
    this.numberingTargets.forEach(g => g.hidden = !g.hidden)
  }
}
