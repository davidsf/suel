class Board < ApplicationRecord
  belongs_to :game_map
  has_one :game_module, through: :game_map
  has_many :scenario_pieces, dependent: :nullify

  def grid_type = grid&.dig("type") || "none"

  # The module's own default: draw the grid lines? (HexGrid "visible" attr)
  def grid_visible?
    g = grid or return false
    return true if g["visible"]
    g["type"] == "zoned" &&
      (g.dig("background", "visible") || (g["zones"] || []).any? { |z| z.dig("grid", "visible") })
  end

  def numbering
    g = grid or return nil
    g = g["background"] if g["type"] == "zoned"
    g.is_a?(Hash) ? g["numbering"] : nil
  end

  def numbering? = numbering.present?

  def numbering_visible? = numbering&.dig("visible") == "true"

  # Nearest legal position per the board's grid (VASSAL snap-on-drop).
  def snap_point(x, y)
    Vassal::GridSnap.snap(grid, x, y)
  end

  # VASSAL-style location name for a board-local point ("1015", a zone...)
  def location_name(x, y)
    Vassal::GridLocation.name(grid, x, y, width: width.to_i, height: height.to_i)
  end
end
