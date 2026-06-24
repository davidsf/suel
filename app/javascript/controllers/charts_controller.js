import { Controller } from "@hotwired/stimulus"

// Tabbed chart gallery: clicking a tab shows its panel.
export default class extends Controller {
  static targets = ["panel"]

  select(event) {
    const index = event.params.index
    this.panelTargets.forEach((panel, i) => { panel.hidden = i !== index })
    this.element.querySelectorAll(".charts-tabs button")
      .forEach((b, i) => b.classList.toggle("active", i === index))
  }
}
