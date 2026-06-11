# Renders board grids as SVG overlays. Hex/square lattices are periodic, so
# they are emitted as a single <pattern> tile instead of one path per cell
# (geometry ported from VASSAL HexGrid.java forceDraw: r = 2dx/3, centers every
# (2dx, dy) with an offset column at (+dx, +dy/2); sideways swaps the axes).
module GridHelper
  def grid_overlay(board)
    grid = board.grid
    return "".html_safe if grid.blank? || board.width.blank?

    content_tag(:svg, class: "grid-overlay", width: board.width, height: board.height,
                viewBox: "0 0 #{board.width} #{board.height}",
                xmlns: "http://www.w3.org/2000/svg", data: { board_target: "grid" }, hidden: true) do
      grid_content(grid)
    end
  end

  def grid_content(grid)
    case grid["type"]
    when "hex" then hex_lattice(grid)
    when "square" then square_lattice(grid)
    when "zoned" then zoned_overlay(grid)
    when "region" then region_overlay(grid)
    else "".html_safe
    end
  end

  def zone_polygons(zones)
    safe_join(zones.map do |zone|
      points = zone["path"].map { |x, y| "#{x},#{y}" }.join(" ")
      content_tag(:g) do
        content_tag(:polygon, nil, points:, fill: "rgba(138,51,36,0.08)",
                    stroke: "rgba(138,51,36,0.8)", "stroke-width": 2) +
          zone_label(zone)
      end
    end)
  end

  private

  def hex_lattice(grid)
    dx = grid["dx"].to_f
    dy = grid["dy"].to_f
    return "".html_safe if dx <= 0 || dy <= 0

    r = 2.0 * dx / 3.0
    sideways = grid["sideways"]
    # Hexagon centered at (0,0) in lattice space
    hex = [ [ -r, 0 ], [ -r / 2, -dy / 2 ], [ r / 2, -dy / 2 ], [ r, 0 ], [ r / 2, dy / 2 ], [ -r / 2, dy / 2 ] ]
    # Hexes overlapping one (2dx × dy) tile: the four corners and the center
    centers = [ [ 0, 0 ], [ 2 * dx, 0 ], [ 0, dy ], [ 2 * dx, dy ], [ dx, dy / 2 ] ]
    tile_w, tile_h = 2 * dx, dy
    origin_x = grid["x0"].to_i
    origin_y = grid["y0"].to_i

    swap = ->(x, y) { sideways ? [ y, x ] : [ x, y ] }
    tile_w, tile_h = tile_h, tile_w if sideways
    origin_x, origin_y = origin_y, origin_x if sideways

    polygons = centers.map do |cx, cy|
      points = hex.map { |px, py| swap.call(cx + px, cy + py).map { |v| v.round(2) }.join(",") }.join(" ")
      %(<polygon points="#{points}" fill="none" stroke="#{grid_color(grid)}" stroke-width="1"/>)
    end.join

    pattern_overlay(polygons, tile_w, tile_h, origin_x, origin_y)
  end

  def square_lattice(grid)
    dx = grid["dx"].to_f
    dy = grid["dy"].to_f
    return "".html_safe if dx <= 0 || dy <= 0

    lines = %(<path d="M 0 0 H #{dx.round(2)} M 0 0 V #{dy.round(2)}" fill="none" stroke="#{grid_color(grid)}" stroke-width="1"/>)
    pattern_overlay(lines, dx, dy, grid["x0"].to_i, grid["y0"].to_i)
  end

  def pattern_overlay(content, width, height, x, y)
    id = "grid-#{SecureRandom.hex(4)}"
    # rubocop:disable Rails/OutputSafety -- numeric/constant interpolations only
    <<~SVG.html_safe
      <defs>
        <pattern id="#{id}" patternUnits="userSpaceOnUse"
                 width="#{width.round(2)}" height="#{height.round(2)}" x="#{x}" y="#{y}">
          #{content}
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill="url(##{id})"/>
    SVG
    # rubocop:enable Rails/OutputSafety
  end

  def zoned_overlay(grid)
    background = grid["background"] ? grid_content(grid["background"]) : "".html_safe
    background + zone_polygons(grid["zones"] || [])
  end

  def zone_label(zone)
    return "".html_safe if zone["name"].blank? || zone["path"].blank?
    cx = zone["path"].sum { |p| p[0] } / zone["path"].size
    cy = zone["path"].sum { |p| p[1] } / zone["path"].size
    content_tag(:text, zone["name"], x: cx, y: cy, "text-anchor": "middle",
                fill: "rgba(138,51,36,0.9)", "font-size": 20)
  end

  def region_overlay(grid)
    safe_join((grid["regions"] || []).map do |region|
      content_tag(:g) do
        content_tag(:circle, nil, cx: region["x"], cy: region["y"], r: 4, fill: "rgba(138,51,36,0.8)") +
          content_tag(:text, region["name"], x: region["x"], y: region["y"] - 8,
                      "text-anchor": "middle", fill: "rgba(138,51,36,0.9)", "font-size": 16)
      end
    end)
  end

  def grid_color(grid)
    if grid["color"].to_s.match?(/\A\d+,\d+,\d+\z/)
      "rgba(#{grid['color']},0.7)"
    else
      "rgba(0,0,0,0.55)"
    end
  end
end
