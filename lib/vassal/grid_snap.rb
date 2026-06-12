module Vassal
  # Snaps a point to the board grid the way VASSAL does on drop
  # (HexGrid#snapToHex: rotate the point if sideways, find the nearest hex
  # center, rotate back; origin is used un-rotated). Zoned grids pick the zone
  # containing the point; region grids snap to the nearest named region.
  module GridSnap
    module_function

    def snap(grid, x, y)
      return [ x, y ] unless grid.is_a?(Hash)

      case grid["type"]
      when "zoned" then snap_zoned(grid, x, y)
      when "hex" then enabled?(grid) ? snap_hex(grid, x, y) : [ x, y ]
      when "square" then enabled?(grid) ? snap_square(grid, x, y) : [ x, y ]
      when "region" then snap_region(grid, x, y)
      else [ x, y ]
      end
    end

    # snapTo defaults to true in VASSAL; older imports may lack the key.
    def enabled?(grid)
      grid["snap"] != false
    end

    def snap_zoned(grid, x, y)
      zone = (grid["zones"] || []).find { |z| contains?(z["path"] || [], x, y) }
      if zone
        return snap(zone["grid"], x, y) if zone["grid"].present? && zone["use_parent_grid"] != true
        return [ x, y ] if zone["use_parent_grid"] == false && zone["grid"].blank?
      end
      snap(grid["background"], x, y)
    end

    def snap_hex(grid, x, y)
      dx = grid["dx"].to_f
      dy = grid["dy"].to_f
      return [ x, y ] if dx <= 0 || dy <= 0

      x0 = grid["x0"].to_i
      y0 = grid["y0"].to_i
      px, py = grid["sideways"] ? [ y, x ] : [ x, y ]

      center = nearest_hex_center(dx, dy, x0, y0, px, py)
      sx, sy = snap_hex_target(grid, dx, dy, x0, y0, px, py, center)

      grid["sideways"] ? [ sy.round, sx.round ] : [ sx.round, sy.round ]
    end

    # HexGrid#snapTo: with edgesLegal/cornersLegal the nearest side midpoint
    # or vertex competes with the center (checkCenter keeps the center when
    # they all but coincide).
    def snap_hex_target(grid, dx, dy, x0, y0, px, py, center)
      edge = grid["edges"] ? hex_side(dx, dy, x0, y0, px, py) : nil
      vertex = grid["corners"] ? hex_vertex(dx, dy, x0, y0, px, py) : nil
      return center unless edge || vertex

      target =
        if edge && vertex
          dist2(px, py, *edge) < dist2(px, py, *vertex) ? edge : vertex
        else
          edge || vertex
        end
      # checkCenter: prefer the true center over a target landing on it
      dist2(*center, *target) <= 2 ? center : target
    end

    def dist2(x1, y1, x2, y2)
      (x1 - x2)**2 + (y1 - y2)**2
    end

    # Ports of HexGrid#sideX/sideY/vertexX/vertexY, integer truncations
    # included (they operate in rotated space like the callers).
    def hex_side(dx, dy, x0, y0, x, y)
      nx = ((x - x0 + dx / 4) * 2 / dx).floor
      sx = (dx / 2 * nx + x0).to_i
      sy =
        if nx.even?
          (dy / 2 * ((y - y0 + dy / 4) * 2 / dy).floor + y0).to_i
        else
          (dy / 2 * ((y - y0) * 2 / dy).floor + (dy / 4).to_i + y0).to_i
        end
      [ sx, sy ]
    end

    def hex_vertex(dx, dy, x0, y0, x, y)
      ny = ((y - y0 + dy / 4) * 2 / dy).floor
      vx =
        if ny.even?
          (2 * dx / 3 * ((x - x0 + dx / 3).floor * 3 / (2 * dx)).to_i + x0).to_i
        else
          (2 * dx / 3 * ((x - x0 + dx / 3 + dx / 3).floor * 3 / (2 * dx)).to_i - (dx / 3).to_i + x0).to_i
        end
      vy = (dy / 2 * ny + y0).to_i
      [ vx, vy ]
    end

    # Hex centers form two rectangular lattices (even columns at x0 + 2dx·i,
    # odd columns shifted by dx and dy/2); the nearest center is the closer of
    # the two lattice candidates.
    def nearest_hex_center(dx, dy, x0, y0, px, py)
      [ 0, 1 ].map do |parity|
        cx0 = x0 + parity * dx
        cy0 = y0 + parity * dy / 2.0
        i = ((px - cx0) / (2 * dx)).round
        j = ((py - cy0) / dy).round
        [ cx0 + i * 2 * dx, cy0 + j * dy ]
      end.min_by { |cx, cy| (cx - px)**2 + (cy - py)**2 }
    end

    def snap_square(grid, x, y)
      dx = grid["dx"].to_f
      dy = grid["dy"].to_f
      return [ x, y ] if dx <= 0 || dy <= 0

      x0 = grid["x0"].to_i
      y0 = grid["y0"].to_i
      [ x0 + ((x - x0) / dx).round * dx, y0 + ((y - y0) / dy).round * dy ].map(&:round)
    end

    def snap_region(grid, x, y)
      regions = (grid["regions"] || []).select { |r| r["x"] && r["y"] }
      return [ x, y ] if regions.empty?

      nearest = regions.min_by { |r| (r["x"] - x)**2 + (r["y"] - y)**2 }
      [ nearest["x"], nearest["y"] ]
    end

    # Ray casting point-in-polygon over the zone path.
    def contains?(path, x, y)
      return false if path.size < 3

      inside = false
      j = path.size - 1
      path.each_with_index do |(xi, yi), i|
        xj, yj = path[j]
        if (yi > y) != (yj > y) &&
            x < (xj - xi).to_f * (y - yi) / (yj - yi) + xi
          inside = !inside
        end
        j = i
      end
      inside
    end
  end
end
