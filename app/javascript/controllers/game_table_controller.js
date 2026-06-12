import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Game table interactions: drag pieces (persisted on drop), click-to-select
// with a floating action toolbar (flip / rotate / cycle layers). Composes
// with pan_zoom: spectators' pointer events fall through to panning; players
// dragging a piece stop propagation so the board doesn't pan underneath.
export default class extends Controller {
  static values = { playable: Boolean }
  static targets = ["toolbar", "pieceName", "flipButton", "rotateLeft", "rotateRight", "layerButtons"]

  connect() {
    this.selectedId = null
    this.reapplySelection = this.reapplySelection.bind(this)
    this.beforeStreamRender = (event) => {
      const original = event.detail.render
      event.detail.render = async (el) => {
        await original(el)
        this.reapplySelection()
      }
    }
    document.addEventListener("turbo:before-stream-render", this.beforeStreamRender)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.beforeStreamRender)
  }

  // --- drag / select -------------------------------------------------------

  pieceDown(event) {
    if (!this.playableValue) return // spectators pan instead
    event.stopPropagation()
    event.preventDefault()

    const piece = event.currentTarget
    piece.setPointerCapture(event.pointerId)

    const scale = this.worldScale()
    const drag = {
      piece,
      scale,
      startX: event.clientX,
      startY: event.clientY,
      startLeft: parseFloat(piece.style.left) || 0,
      startTop: parseFloat(piece.style.top) || 0,
      moved: false
    }

    const onMove = (e) => {
      const dx = (e.clientX - drag.startX) / drag.scale
      const dy = (e.clientY - drag.startY) / drag.scale
      if (Math.abs(e.clientX - drag.startX) + Math.abs(e.clientY - drag.startY) > 4) drag.moved = true
      piece.style.left = `${drag.startLeft + dx}px`
      piece.style.top = `${drag.startTop + dy}px`
      if (drag.moved) piece.style.zIndex = 100000
    }

    const onUp = () => {
      piece.removeEventListener("pointermove", onMove)
      piece.removeEventListener("pointerup", onUp)
      piece.removeEventListener("pointercancel", onUp)
      if (drag.moved) {
        this.patch(piece.dataset.moveUrl, {
          x: Math.round(parseFloat(piece.style.left)),
          y: Math.round(parseFloat(piece.style.top))
        })
      } else {
        this.select(piece)
      }
    }

    piece.addEventListener("pointermove", onMove)
    piece.addEventListener("pointerup", onUp)
    piece.addEventListener("pointercancel", onUp)
  }

  worldScale() {
    const world = this.element.querySelector(".world")
    const matrix = new DOMMatrix(getComputedStyle(world).transform)
    return matrix.a || 1
  }

  select(piece) {
    this.clearSelection()
    this.selectedId = piece.id
    piece.classList.add("selected")
    this.showToolbar(piece)
  }

  clearSelection() {
    this.element.querySelectorAll(".table-piece.selected")
      .forEach(el => el.classList.remove("selected"))
  }

  reapplySelection() {
    if (!this.selectedId) return
    const piece = document.getElementById(this.selectedId)
    if (piece) {
      piece.classList.add("selected")
    } else {
      this.selectedId = null
      this.toolbarTarget.hidden = true
    }
  }

  selectedPiece() {
    return this.selectedId && document.getElementById(this.selectedId)
  }

  // --- floating toolbar ----------------------------------------------------

  showToolbar(piece) {
    this.pieceNameTarget.textContent = piece.title
    this.flipButtonTarget.hidden = piece.dataset.flippable !== "true"
    const rotatable = piece.dataset.rotatable === "true"
    this.rotateLeftTarget.hidden = !rotatable
    this.rotateRightTarget.hidden = !rotatable

    this.layerButtonsTarget.replaceChildren()
    JSON.parse(piece.dataset.layers || "[]").forEach((name, index) => {
      const button = document.createElement("button")
      button.textContent = name
      button.addEventListener("click", () => this.cycleLayer(index))
      this.layerButtonsTarget.appendChild(button)
    })

    this.toolbarTarget.hidden = false
  }

  flip() {
    const piece = this.selectedPiece()
    if (piece) this.patch(piece.dataset.flipUrl, {})
  }

  rotateLeft() { this.rotate(-1) }
  rotateRight() { this.rotate(1) }

  rotate(direction) {
    const piece = this.selectedPiece()
    if (piece) this.patch(piece.dataset.rotateUrl, { direction })
  }

  cycleLayer(index) {
    const piece = this.selectedPiece()
    if (piece) this.patch(piece.dataset.cycleLayerUrl, { index, delta: 1 })
  }

  // --- server sync ---------------------------------------------------------

  async patch(url, params) {
    const body = new URLSearchParams(params)
    const response = await fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body
    })
    if (response.ok) {
      Turbo.renderStreamMessage(await response.text())
    }
  }
}
