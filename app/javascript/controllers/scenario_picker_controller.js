import { Controller } from "@hotwired/stimulus"

// Opens the scenario list in a modal when a game card loads it into the shared
// turbo-frame, so the choices appear over the grid instead of below it.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    // showModal() throws if the dialog is already open (re-click while open).
    if (this.hasDialogTarget && !this.dialogTarget.open) this.dialogTarget.showModal()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) this.dialogTarget.close()
  }
}
