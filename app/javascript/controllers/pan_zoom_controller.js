import { Controller } from "@hotwired/stimulus"

// Pan/zoom for the board viewer. A single "world" element is translated and
// scaled; everything inside (board image, grid overlay, pieces) moves with it.
export default class extends Controller {
  static targets = ["world", "viewport"]
  static values = {
    width: Number,
    height: Number,
    minScale: { type: Number, default: 0.05 },
    maxScale: { type: Number, default: 4 }
  }

  connect() {
    this.x = 0
    this.y = 0
    this.scale = 1
    this.pointers = new Map()
    this.fit()
  }

  // Fit the board into the viewport on load
  fit() {
    if (!this.widthValue) return
    const rect = this.viewportTarget.getBoundingClientRect()
    this.scale = Math.min(rect.width / this.widthValue, rect.height / this.heightValue, 1)
    this.scale = Math.max(this.scale, this.minScaleValue)
    this.x = (rect.width - this.widthValue * this.scale) / 2
    this.y = Math.max((rect.height - this.heightValue * this.scale) / 2, 0)
    this.apply()
  }

  wheel(event) {
    event.preventDefault()
    const factor = Math.exp(-event.deltaY * 0.0015)
    const rect = this.viewportTarget.getBoundingClientRect()
    this.zoomAt(event.clientX - rect.left, event.clientY - rect.top, factor)
  }

  zoomAt(px, py, factor) {
    const next = Math.min(Math.max(this.scale * factor, this.minScaleValue), this.maxScaleValue)
    const ratio = next / this.scale
    this.x = px - (px - this.x) * ratio
    this.y = py - (py - this.y) * ratio
    this.scale = next
    this.apply()
  }

  zoomIn() { this.zoomCenter(1.25) }
  zoomOut() { this.zoomCenter(0.8) }

  zoomCenter(factor) {
    const rect = this.viewportTarget.getBoundingClientRect()
    this.zoomAt(rect.width / 2, rect.height / 2, factor)
  }

  pointerDown(event) {
    this.viewportTarget.setPointerCapture(event.pointerId)
    this.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY })
  }

  pointerMove(event) {
    const pointer = this.pointers.get(event.pointerId)
    if (!pointer) return

    if (this.pointers.size === 2) {
      this.pinch(event)
    } else {
      this.x += event.clientX - pointer.x
      this.y += event.clientY - pointer.y
      this.apply()
    }
    pointer.x = event.clientX
    pointer.y = event.clientY
  }

  pinch(event) {
    const others = [...this.pointers.entries()].filter(([id]) => id !== event.pointerId)
    if (!others.length) return
    const other = others[0][1]
    const previous = this.pointers.get(event.pointerId)
    const before = Math.hypot(previous.x - other.x, previous.y - other.y)
    const after = Math.hypot(event.clientX - other.x, event.clientY - other.y)
    if (before > 0) {
      const rect = this.viewportTarget.getBoundingClientRect()
      const cx = (event.clientX + other.x) / 2 - rect.left
      const cy = (event.clientY + other.y) / 2 - rect.top
      this.zoomAt(cx, cy, after / before)
    }
  }

  pointerUp(event) {
    this.pointers.delete(event.pointerId)
  }

  apply() {
    this.worldTarget.style.transform =
      `translate(${this.x}px, ${this.y}px) scale(${this.scale})`
  }
}
