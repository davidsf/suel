import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Game table interactions: drag pieces (persisted on drop), click-to-select
// with a floating action toolbar (flip / rotate / cycle layers). Composes
// with pan_zoom: spectators' pointer events fall through to panning; players
// dragging a piece stop propagation so the board doesn't pan underneath.
export default class extends Controller {
  static values = { playable: Boolean, snapUrl: String, map: Number, maps: Array, decks: Array,
                    relocateUrlTemplate: String, i18n: Object }
  static targets = ["toolbar", "pieceName", "flipButton", "rotateRow", "rotateLeft", "rotateRight", "layerButtons",
                    "deckToolbar", "deckName", "drawButton", "reshuffleButton",
                    "handTray", "handOpen", "chartsDialog"]

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

        // In placement mode a click drops the in-flight piece on this map.
        if (this.placingId) { this.placeAt(e.clientX, e.clientY); return }

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
        this.hideActionToolbars()
      }
      this.viewport.addEventListener("pointerdown", this.onViewportDown)
      this.viewport.addEventListener("pointerup", this.onViewportUp)
    }

    this.layoutStacks()

    // Arriving with ?place=<id> means we navigated here to drop a piece coming
    // from another map (the "move to another map" flow).
    const placeId = new URLSearchParams(location.search).get("place")
    if (placeId && this.playableValue) this.enterPlacement(placeId)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.beforeStreamRender)
    if (this.viewport) {
      this.viewport.removeEventListener("pointerdown", this.onViewportDown)
      this.viewport.removeEventListener("pointerup", this.onViewportUp)
    }
    if (this.placingId) {
      document.removeEventListener("pointermove", this.onPlacementMove)
      document.removeEventListener("keydown", this.onPlacementKey)
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
    if (event.button !== 0) return // right/middle click is handled by pieceContext
    event.stopPropagation()
    event.preventDefault()

    const piece = event.currentTarget
    try { piece.setPointerCapture(event.pointerId) } catch {}

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
        const world = { x: Math.round(parseFloat(piece.style.left)), y: Math.round(parseFloat(piece.style.top)) }
        const deck = this.deckAt(world)
        if (deck) this.patch(piece.dataset.discardUrl, { deck: deck.dataset.deckId })
        else this.patch(piece.dataset.moveUrl, { x: world.x, y: world.y })
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

  // Screen (viewport-page) coords → world (map) coords through the inverse of
  // the world transform. Returns null when the point is outside the viewer.
  screenToWorld(clientX, clientY) {
    const rect = this.viewport.getBoundingClientRect()
    if (clientX < rect.left || clientX > rect.right || clientY < rect.top || clientY > rect.bottom) return null
    const world = this.element.querySelector(".world")
    const point = new DOMPoint(clientX - rect.left, clientY - rect.top)
    const local = point.matrixTransform(new DOMMatrix(getComputedStyle(world).transform).inverse())
    return { x: Math.round(local.x), y: Math.round(local.y) }
  }

  // --- hand cards -----------------------------------------------------------

  // Drag a card from the tray onto the board to play it; a tiny move selects
  // it instead (showing the discard toolbar).
  handCardDown(event) {
    event.stopPropagation()
    event.preventDefault()
    const card = event.currentTarget
    card.setPointerCapture(event.pointerId)

    const drag = { startX: event.clientX, startY: event.clientY, moved: false, clone: null }

    const onMove = (e) => {
      if (Math.abs(e.clientX - drag.startX) + Math.abs(e.clientY - drag.startY) > 4) drag.moved = true
      if (!drag.moved) return
      if (!drag.clone) {
        drag.clone = card.cloneNode(true)
        drag.clone.classList.add("drag-clone")
        document.body.appendChild(drag.clone)
        card.style.opacity = "0.4"
      }
      drag.clone.style.left = `${e.clientX}px`
      drag.clone.style.top = `${e.clientY}px`
      const world = this.screenToWorld(e.clientX, e.clientY)
      if (world) this.previewGhostAt(world); else this.hideGhost()
    }

    const onUp = (e) => {
      card.removeEventListener("pointermove", onMove)
      card.removeEventListener("pointerup", onUp)
      card.removeEventListener("pointercancel", onUp)
      this.hideGhost()
      drag.clone?.remove()
      card.style.opacity = ""

      if (drag.moved) {
        const world = this.screenToWorld(e.clientX, e.clientY)
        const deck = this.deckAt(world)
        if (deck) this.patch(card.dataset.discardUrl, { deck: deck.dataset.deckId })
        else if (world) this.patch(card.dataset.playUrl, { map: this.mapValue, x: world.x, y: world.y })
      }
    }

    card.addEventListener("pointermove", onMove)
    card.addEventListener("pointerup", onUp)
    card.addEventListener("pointercancel", onUp)
  }

  // Throttled snap ghost for a known world point (hand-card drag).
  previewGhostAt(world) {
    const now = performance.now()
    if (now - (this.lastSnapAt || 0) < 80) return
    this.lastSnapAt = now
    const seq = (this.snapSeq = (this.snapSeq || 0) + 1)
    fetch(`${this.snapUrlValue}?map=${this.mapValue}&x=${world.x}&y=${world.y}`,
          { headers: { "Accept": "application/json" } })
      .then(r => r.ok ? r.json() : null)
      .then(data => { if (data && seq === this.snapSeq) this.showGhost(data) })
      .catch(() => {})
  }

  closeTray() {
    this.handTrayTarget.hidden = true
    this.handOpenTarget.hidden = false
  }

  openTray() {
    this.handTrayTarget.hidden = false
    this.handOpenTarget.hidden = true
  }

  // The actionable deck marker (on the board, not the tray) whose footprint
  // contains the world point — VASSAL adds a dragged piece to a deck it is
  // dropped on (PieceMover.visitDeck). Markers are centred on left/top.
  deckAt(world) {
    if (!world) return null
    return [...this.element.querySelectorAll(".world .deck-marker.actionable")].find(marker => {
      const dx = Math.abs(world.x - parseFloat(marker.style.left))
      const dy = Math.abs(world.y - parseFloat(marker.style.top))
      return dx <= marker.offsetWidth / 2 && dy <= marker.offsetHeight / 2
    }) || null
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
    // A right-click / long-press just opened the menu via pieceContext; ignore
    // the click that the same gesture delivers so it doesn't dismiss the menu.
    if (Date.now() - (this.menuOpenedAt || 0) < 500) return
    if (this.toggleStack(piece)) return

    const stacked = (this.stacks().get(this.stackKey(piece)) || []).length > 1

    // A single click/tap just selects; a second one on the same piece within
    // the threshold opens the action menu (double-click / double-tap).
    const now = Date.now()
    const doubled = this.lastTapId === piece.id && now - (this.lastTapAt || 0) < 350
    this.lastTapId = piece.id
    this.lastTapAt = now

    if (doubled) this.openMenu(piece)
    else this.select(piece)

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

  // Highlight a piece without opening the action menu (single click/tap).
  select(piece) {
    this.clearSelection()
    if (this.hasDeckToolbarTarget) this.deckToolbarTarget.hidden = true
    if (this.hasToolbarTarget) this.toolbarTarget.hidden = true
    this.selectedId = piece.id
    piece.classList.add("selected")
  }

  // Select and open the action menu (double click/tap, or right-click).
  openMenu(piece) {
    const el = document.getElementById(piece.id) || piece
    this.select(el)
    this.showToolbar(el)
  }

  hideActionToolbars() {
    if (this.hasToolbarTarget) this.toolbarTarget.hidden = true
    if (this.hasDeckToolbarTarget) this.deckToolbarTarget.hidden = true
  }

  // Places a fixed toolbar just below the element it acts on, clamped to the
  // viewport (above the element if there's no room below).
  positionToolbar(toolbarEl, anchorEl) {
    toolbarEl.hidden = false
    const r = anchorEl.getBoundingClientRect()
    const tw = toolbarEl.offsetWidth, th = toolbarEl.offsetHeight
    let left = r.left + r.width / 2 - tw / 2
    left = Math.max(4, Math.min(left, window.innerWidth - tw - 4))
    let top = r.bottom + 6
    if (top + th > window.innerHeight - 4) top = Math.max(4, r.top - th - 6)
    toolbarEl.style.left = `${left}px`
    toolbarEl.style.top = `${top}px`
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
      // Rebuild an open menu from the piece's new state so chosen options
      // (toggled markers, stepped levels) reflect live without reopening it.
      if (this.hasToolbarTarget && !this.toolbarTarget.hidden) this.showToolbar(piece)
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
    this.rotateRowTarget.hidden = piece.dataset.rotatable !== "true"

    // One menu row per layer trait: on/off layers show ✓/— and toggle on
    // click; multi-level layers show the current level (name or number) with
    // ◀ ▶ steppers.
    this.layerButtonsTarget.replaceChildren()
    JSON.parse(piece.dataset.layers || "[]").forEach((layer, index) => {
      const label = layer.name
      if (layer.toggle) {
        const row = document.createElement("button")
        row.type = "button"
        row.className = "menu-row clickable"
        row.title = `${label}: ${this.i18nValue.toggle}`
        row.append(this.menuLabel(label), this.menuState(layer.active ? "✓" : "—"))
        row.addEventListener("click", () => this.cycleLayer(index, 1))
        this.layerButtonsTarget.appendChild(row)
      } else {
        const row = document.createElement("div")
        row.className = "menu-row"
        const stepper = document.createElement("span")
        stepper.className = "menu-stepper"
        const state = layer.active ? (layer.level_name || String(layer.level)) : "—"
        stepper.append(
          this.menuStepButton("◀", `${label}: ${this.i18nValue.prev_level}`, index, -1),
          this.menuState(state),
          this.menuStepButton("▶", `${label}: ${this.i18nValue.next_level}`, index, 1)
        )
        row.append(this.menuLabel(label), stepper)
        this.layerButtonsTarget.appendChild(row)
      }
    })

    // Numeric dynamic properties (e.g. a hit counter) as − value + steppers.
    JSON.parse(piece.dataset.properties || "[]").forEach((prop) => {
      const row = document.createElement("div")
      row.className = "menu-row"
      const stepper = document.createElement("span")
      stepper.className = "menu-stepper"
      stepper.append(
        this.propStepButton("−", `${prop.label}: -1`, prop.index, -1),
        this.menuState(String(prop.value)),
        this.propStepButton("+", `${prop.label}: +1`, prop.index, 1)
      )
      row.append(this.menuLabel(prop.label), stepper)
      this.layerButtonsTarget.appendChild(row)
    })

    // VASSAL key commands (Reveal, Send to..., etc.) as clickable rows. The
    // server runs the command and broadcasts every affected piece, so we just
    // fire and let the menu close. A ReturnToDeck that prompts for the
    // destination (VASSAL's deck-selection dialog) becomes a deck submenu.
    JSON.parse(piece.dataset.commands || "[]").forEach((command) => {
      if (command.prompt_deck) {
        if (this.decksValue.length > 0)
          this.appendSubmenu(command.label, this.decksValue, deck => this.runCommand(command.key, deck.id))
        return
      }
      const row = document.createElement("button")
      row.type = "button"
      row.className = "menu-row clickable"
      row.title = command.label
      row.append(this.menuLabel(command.label))
      row.addEventListener("click", () => this.runCommand(command.key))
      this.layerButtonsTarget.appendChild(row)
    })

    // "Move to another map" — the web equivalent of dragging a piece between
    // VASSAL's separate map windows; choosing one navigates there in placement
    // mode (carry the piece, click to drop).
    if (this.mapsValue.length > 0) {
      this.appendSubmenu(this.i18nValue.move_to_map, this.mapsValue, map => this.moveToMap(map, piece))
    }

    this.positionToolbar(this.toolbarTarget, piece)
  }

  // A collapsible "label ▸" menu row revealing one button per item ({name}).
  // Expansion is remembered per label across rebuilds (broadcasts re-render an
  // open menu). Collapsible because modules can have many maps or decks; a
  // flat list would swamp the menu.
  appendSubmenu(label, items, onPick) {
    this.submenuOpen ||= {}
    const submenu = document.createElement("div")
    submenu.className = "menu-submenu"
    submenu.hidden = !this.submenuOpen[label]
    items.forEach((item) => {
      const row = document.createElement("button")
      row.type = "button"
      row.className = "menu-row clickable"
      row.append(this.menuLabel(item.name))
      row.addEventListener("click", () => onPick(item))
      submenu.appendChild(row)
    })

    const toggle = document.createElement("button")
    toggle.type = "button"
    toggle.className = "menu-row clickable"
    const caret = this.menuState(this.submenuOpen[label] ? "▾" : "▸")
    toggle.append(this.menuLabel(label), caret)
    toggle.addEventListener("click", () => {
      this.submenuOpen[label] = !this.submenuOpen[label]
      submenu.hidden = !this.submenuOpen[label]
      caret.textContent = this.submenuOpen[label] ? "▾" : "▸"
      // Re-clamp: expanding grows the menu and it may need to flip above.
      const piece = this.selectedPiece()
      if (piece) this.positionToolbar(this.toolbarTarget, piece)
    })

    this.layerButtonsTarget.append(toggle, submenu)
  }

  runCommand(key, deckId = null) {
    const piece = this.selectedPiece()
    if (!piece) return
    const params = deckId ? { command: key, deck: deckId } : { command: key }
    this.send(piece.dataset.commandUrl, "POST", params)
    this.hideActionToolbars()
    this.selectedId = null
  }

  // --- move to another map -------------------------------------------------

  // Navigate to the chosen map carrying the piece id, so the destination page
  // loads in placement mode (the piece still lives on its source map server-side
  // until the drop lands).
  moveToMap(map, piece) {
    this.hideActionToolbars()
    this.selectedId = null
    const sep = map.url.includes("?") ? "&" : "?"
    Turbo.visit(`${map.url}${sep}place=${piece.dataset.pieceId}`)
  }

  enterPlacement(pieceId) {
    this.placingId = pieceId
    this.showPlacementBanner()
    this.onPlacementMove = (e) => {
      const world = this.screenToWorld(e.clientX, e.clientY)
      if (world) this.previewGhostAt(world); else this.hideGhost()
    }
    this.onPlacementKey = (e) => { if (e.key === "Escape") this.exitPlacement() }
    document.addEventListener("pointermove", this.onPlacementMove)
    document.addEventListener("keydown", this.onPlacementKey)
  }

  placeAt(clientX, clientY) {
    const world = this.screenToWorld(clientX, clientY)
    if (!world) return
    const url = this.relocateUrlTemplateValue.replace("PIECE_ID", this.placingId)
    this.send(url, "PATCH", { map: this.mapValue, x: world.x, y: world.y })
    this.exitPlacement()
  }

  exitPlacement() {
    if (!this.placingId) return
    this.placingId = null
    this.hideGhost()
    document.removeEventListener("pointermove", this.onPlacementMove)
    document.removeEventListener("keydown", this.onPlacementKey)
    this.hidePlacementBanner()
    // Drop ?place= so a refresh doesn't re-enter placement.
    const url = new URL(location.href)
    url.searchParams.delete("place")
    history.replaceState({}, "", url)
  }

  showPlacementBanner() {
    if (!this.placementBanner) {
      this.placementBanner = document.createElement("div")
      this.placementBanner.className = "placement-banner"
      const text = document.createElement("span")
      text.textContent = this.i18nValue.placement_hint
      const cancel = document.createElement("button")
      cancel.type = "button"
      cancel.textContent = this.i18nValue.cancel
      cancel.addEventListener("click", () => this.exitPlacement())
      this.placementBanner.append(text, cancel)
      this.element.appendChild(this.placementBanner)
    }
    this.placementBanner.hidden = false
  }

  hidePlacementBanner() {
    if (this.placementBanner) this.placementBanner.hidden = true
  }

  propStepButton(text, title, index, delta) {
    const button = document.createElement("button")
    button.type = "button"
    button.textContent = text
    button.title = title
    button.addEventListener("click", () => this.adjustProperty(index, delta))
    return button
  }

  adjustProperty(index, delta) {
    const piece = this.selectedPiece()
    if (piece) this.patch(piece.dataset.adjustPropertyUrl, { index, delta })
  }

  menuLabel(text) {
    const span = document.createElement("span")
    span.className = "menu-label"
    span.textContent = text
    return span
  }

  menuState(text) {
    const span = document.createElement("span")
    span.className = "menu-state"
    span.textContent = text
    return span
  }

  menuStepButton(text, title, index, delta) {
    const button = document.createElement("button")
    button.type = "button"
    button.textContent = text
    button.title = title
    button.addEventListener("click", () => this.cycleLayer(index, delta))
    return button
  }

  // Right-click on a piece opens the action menu directly (a single tap only
  // selects; a double tap is the touch equivalent).
  pieceContext(event) {
    if (!this.playableValue) return
    event.preventDefault()
    this.menuOpenedAt = Date.now()
    this.openMenu(event.currentTarget)
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

  openCharts() {
    if (this.hasChartsDialogTarget) this.chartsDialogTarget.showModal()
  }

  // --- decks ----------------------------------------------------------------

  // Hand decks (on a player-hand map) draw via the toolbar button into the
  // tray. Board decks (cups) are drawn VASSAL-style: drag the top piece out
  // onto the table; a plain click just selects (shows shuffle/reshuffle).
  deckDown(event) {
    if (!this.playableValue) return
    if (event.button !== 0) return
    event.stopPropagation()
    const marker = event.currentTarget

    const draggable = marker.dataset.drawMode !== "hand" && marker.dataset.drawUrl
    if (!draggable) { this.selectDeck(marker); return }

    // Stop the browser's native image drag (the marker shows the top piece);
    // otherwise it cancels our pointer drag before the drop lands.
    event.preventDefault()
    try { marker.setPointerCapture(event.pointerId) } catch {}
    const drag = { startX: event.clientX, startY: event.clientY, moved: false, clone: null }

    const onMove = (e) => {
      if (Math.abs(e.clientX - drag.startX) + Math.abs(e.clientY - drag.startY) > 4) drag.moved = true
      if (!drag.moved) return
      if (!drag.clone) {
        drag.clone = marker.cloneNode(true)
        drag.clone.classList.add("drag-clone")
        drag.clone.querySelector(".deck-label")?.remove()
        document.body.appendChild(drag.clone)
      }
      drag.clone.style.left = `${e.clientX}px`
      drag.clone.style.top = `${e.clientY}px`
      const world = this.screenToWorld(e.clientX, e.clientY)
      if (world) this.previewGhostAt(world); else this.hideGhost()
    }

    const onUp = (e) => {
      marker.removeEventListener("pointermove", onMove)
      marker.removeEventListener("pointerup", onUp)
      marker.removeEventListener("pointercancel", onUp)
      this.hideGhost()
      drag.clone?.remove()

      if (drag.moved) {
        const world = this.screenToWorld(e.clientX, e.clientY)
        if (world) this.send(marker.dataset.drawUrl, "POST", { map: this.mapValue, x: world.x, y: world.y })
      } else {
        this.selectDeck(marker)
      }
    }

    marker.addEventListener("pointermove", onMove)
    marker.addEventListener("pointerup", onUp)
    marker.addEventListener("pointercancel", onUp)
  }

  selectDeck(marker) {
    this.selectedDeck = marker
    this.deckNameTarget.textContent = `${marker.dataset.deckName} (${marker.dataset.count})`
    // "Robar" draws to the hand: only for hand decks (cups are drawn by dragging).
    this.drawButtonTarget.hidden = marker.dataset.drawMode !== "hand" || !marker.dataset.drawUrl
    this.reshuffleButtonTarget.hidden = !marker.dataset.reshuffleUrl
    // Selecting a deck dismisses the piece toolbar and clears piece selection
    if (this.hasToolbarTarget) this.toolbarTarget.hidden = true
    this.clearSelection()
    this.selectedId = null
    this.positionToolbar(this.deckToolbarTarget, marker)
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
