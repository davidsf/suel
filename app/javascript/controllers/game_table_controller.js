import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Game table interactions: drag pieces (persisted on drop), click-to-select
// with a floating action toolbar (flip / rotate / cycle layers). Composes
// with pan_zoom: spectators' pointer events fall through to panning; players
// dragging a piece stop propagation so the board doesn't pan underneath.
export default class extends Controller {
  static values = { playable: Boolean, snapUrl: String, map: Number }
  static targets = ["toolbar", "pieceName", "flipButton", "rotateLeft", "rotateRight", "layerButtons",
                    "deckToolbar", "deckName", "drawButton", "reshuffleButton"]

  connect() {
    this.selectedId = null
    this.expandedStack = null
    this.beforeStreamRender = (event) => {
      const original = event.detail.render
      event.detail.render = async (el) => {
        await original(el)
        this.reapplySelection()
        this.layoutStacks()
      }
    }
    document.addEventListener("turbo:before-stream-render", this.beforeStreamRender)

    // Plain click on the background (not a piece, not a pan) collapses the
    // expanded stack and clears the selection.
    this.viewport = this.element.querySelector(".viewer")
    if (this.viewport) {
      this.onViewportDown = (e) => { this.viewportDownAt = { x: e.clientX, y: e.clientY } }
      this.onViewportUp = (e) => {
        const start = this.viewportDownAt
        this.viewportDownAt = null
        if (!start || Math.abs(e.clientX - start.x) + Math.abs(e.clientY - start.y) >= 4) return

        // Spectators' piece events bubble here: let them expand stacks too
        const piece = e.target.closest(".table-piece")
        if (piece && !this.playableValue) {
          this.toggleStack(piece)
          return
        }
        if (piece) return // players handle their clicks in pieceDown

        this.collapseStacks()
        this.clearSelection()
        this.selectedId = null
        if (this.hasToolbarTarget) this.toolbarTarget.hidden = true
      }
      this.viewport.addEventListener("pointerdown", this.onViewportDown)
      this.viewport.addEventListener("pointerup", this.onViewportUp)
    }

    this.layoutStacks()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.beforeStreamRender)
    if (this.viewport) {
      this.viewport.removeEventListener("pointerdown", this.onViewportDown)
      this.viewport.removeEventListener("pointerup", this.onViewportUp)
    }
  }

  // --- stacks ---------------------------------------------------------------

  stackKey(piece) {
    return `${Math.round(parseFloat(piece.style.left))},${Math.round(parseFloat(piece.style.top))}`
  }

  stacks() {
    const groups = new Map()
    this.element.querySelectorAll(".table-piece").forEach(piece => {
      const key = this.stackKey(piece)
      if (!groups.has(key)) groups.set(key, [])
      groups.get(key).push(piece)
    })
    groups.forEach(group => group.sort((a, b) => (parseInt(a.style.zIndex) || 0) - (parseInt(b.style.zIndex) || 0)))
    return groups
  }

  // Collapsed stacks cascade a few pixels (VASSAL style); the expanded one
  // fans out so each piece can be picked.
  layoutStacks() {
    this.stacks().forEach((group, key) => {
      const expanded = key === this.expandedStack
      group.forEach((piece, index) => {
        if (group.length === 1) {
          piece.style.translate = ""
        } else if (expanded) {
          piece.style.translate = `${index * 30}px 0`
        } else {
          piece.style.translate = `${index * 5}px ${-index * 5}px`
        }
        piece.classList.toggle("stacked", group.length > 1 && !expanded)
      })
    })
  }

  collapseStacks() {
    this.expandedStack = null
    this.layoutStacks()
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
      if (drag.moved) {
        piece.style.zIndex = 100000
        piece.style.translate = "" // leave any stack fan; drag uses real coords
        this.previewSnap(piece)
      }
    }

    const onUp = () => {
      piece.removeEventListener("pointermove", onMove)
      piece.removeEventListener("pointerup", onUp)
      piece.removeEventListener("pointercancel", onUp)
      this.hideGhost()
      if (drag.moved) {
        this.patch(piece.dataset.moveUrl, {
          x: Math.round(parseFloat(piece.style.left)),
          y: Math.round(parseFloat(piece.style.top))
        })
      } else {
        this.pieceClicked(piece)
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

  // --- snap ghost ----------------------------------------------------------

  // Throttled server-side snap preview: shows where the piece will land.
  previewSnap(piece) {
    if (!this.snapUrlValue) return
    const now = performance.now()
    if (now - (this.lastSnapAt || 0) < 80) return
    this.lastSnapAt = now

    const x = Math.round(parseFloat(piece.style.left))
    const y = Math.round(parseFloat(piece.style.top))
    const seq = (this.snapSeq = (this.snapSeq || 0) + 1)
    fetch(`${this.snapUrlValue}?map=${this.mapValue}&x=${x}&y=${y}`,
          { headers: { "Accept": "application/json" } })
      .then(response => response.ok ? response.json() : null)
      .then(data => {
        if (data && seq === this.snapSeq) this.showGhost(data)
      })
      .catch(() => {})
  }

  showGhost(data) {
    if (!this.ghost) {
      this.ghost = document.createElement("div")
      this.ghost.className = "snap-ghost"
      this.ghost.innerHTML = "<span></span>"
      this.element.querySelector(".world").appendChild(this.ghost)
    }
    this.ghost.style.left = `${data.x}px`
    this.ghost.style.top = `${data.y}px`
    this.ghost.querySelector("span").textContent = data.location || ""
    this.ghost.hidden = false
  }

  hideGhost() {
    this.snapSeq = (this.snapSeq || 0) + 1 // discard in-flight previews
    if (this.ghost) this.ghost.hidden = true
  }

  // First click on a collapsed stack expands it; clicking an expanded piece
  // selects it and brings it to the top of the stack; lone pieces just select.
  pieceClicked(piece) {
    if (this.toggleStack(piece)) return

    const stacked = (this.stacks().get(this.stackKey(piece)) || []).length > 1
    this.select(piece)
    if (stacked) {
      this.patch(piece.dataset.moveUrl, {
        x: Math.round(parseFloat(piece.style.left)),
        y: Math.round(parseFloat(piece.style.top))
      })
    }
  }

  // Expands the piece's stack if it was collapsed. Returns true when it did.
  toggleStack(piece) {
    const key = this.stackKey(piece)
    const stack = this.stacks().get(key) || []
    if (stack.length <= 1 || this.expandedStack === key) return false

    this.expandedStack = key
    this.layoutStacks()
    this.clearSelection()
    this.selectedId = null
    if (this.hasToolbarTarget) this.toolbarTarget.hidden = true
    return true
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
    JSON.parse(piece.dataset.layers || "[]").forEach((layer, index) => {
      const group = document.createElement("span")
      group.className = "layer-group"

      if (layer.toggle) {
        // On/off layer: a single toggle button
        const toggle = this.layerButton(layer.name, `${layer.name}: alternar`, index, 1)
        group.append(toggle)
      } else {
        group.append(
          this.layerButton(`${layer.name} −`, `${layer.name}: nivel anterior`, index, -1),
          this.layerButton(`${layer.name} +`, `${layer.name}: siguiente nivel`, index, 1)
        )
      }
      this.layerButtonsTarget.appendChild(group)
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

  layerButton(text, title, index, delta) {
    const button = document.createElement("button")
    button.type = "button"
    button.textContent = text
    button.title = title
    button.addEventListener("click", () => this.cycleLayer(index, delta))
    return button
  }

  cycleLayer(index, delta = 1) {
    const piece = this.selectedPiece()
    if (piece) this.patch(piece.dataset.cycleLayerUrl, { index, delta })
  }

  roll(event) {
    fetch(event.params.url, {
      method: "POST",
      headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content }
    })
  }

  // --- decks ----------------------------------------------------------------

  deckDown(event) {
    if (!this.playableValue) return
    event.stopPropagation()
    const marker = event.currentTarget
    this.selectedDeck = marker
    this.deckNameTarget.textContent = `${marker.dataset.deckName} (${marker.dataset.count})`
    this.drawButtonTarget.hidden = !marker.dataset.drawUrl
    this.reshuffleButtonTarget.hidden = !marker.dataset.reshuffleUrl
    this.deckToolbarTarget.hidden = false
    // Selecting a deck dismisses the piece toolbar
    if (this.hasToolbarTarget) this.toolbarTarget.hidden = true
  }

  draw() { this.deckAction("drawUrl", "POST") }
  shuffleDeck() { this.deckAction("shuffleUrl", "POST") }
  reshuffleDeck() { this.deckAction("reshuffleUrl", "POST") }

  deckAction(urlKey, method) {
    const url = this.selectedDeck?.dataset[urlKey]
    if (url) this.send(url, method)
  }

  // --- server sync ---------------------------------------------------------

  patch(url, params) { return this.send(url, "PATCH", params) }

  async send(url, method, params = {}) {
    const response = await fetch(url, {
      method,
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: new URLSearchParams(params)
    })
    if (response.ok && response.headers.get("content-type")?.includes("turbo-stream")) {
      Turbo.renderStreamMessage(await response.text())
    }
  }
}
