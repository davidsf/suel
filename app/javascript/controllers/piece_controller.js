import { Controller } from "@hotwired/stimulus"

// Flip a piece between its front image and the mask/back image.
export default class extends Controller {
  static targets = ["front"]

  flip(event) {
    if (!this.hasFrontTarget) return
    const back = event.params.back
    if (!this.originalSrc) this.originalSrc = this.frontTarget.src
    this.frontTarget.src =
      this.frontTarget.src === back ? this.originalSrc : back
  }
}
