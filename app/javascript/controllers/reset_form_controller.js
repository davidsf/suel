import { Controller } from "@hotwired/stimulus"

// Clears a form after a successful Turbo submission (e.g. the chat input).
export default class extends Controller {
  reset(event) {
    if (event.detail.success) this.element.reset()
  }
}
