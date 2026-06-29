module Vassal
  # Names a point on a board the way VASSAL does ("1015", "Turn 3", a zone
  # name...): the inverse of GridNumbering. Zoned grids name through the zone
  # containing the point (honoring its locationFormat), region grids through
  # the nearest named region.
  module GridLocation
    module_function

    def name(grid, x, y, width:, height:)
      return nil unless grid.is_a?(Hash)

      case grid["type"]
      when "zoned" then zoned_name(grid, x, y, width:, height:)
      when "hex" then hex_cell_name(grid, x, y, width:, height:)
      when "square" then square_cell_name(grid, x, y, width:, height:)
      when "region" then region_name(grid, x, y)
      end
    end

    def zoned_name(grid, x, y, width:, height:)
      zone = (grid["zones"] || []).find { |z| GridSnap.contains?(z["path"] || [], x, y) }
      return name(grid["background"], x, y, width:, height:) unless zone

      inner =
        if zone["grid"].present? && zone["use_parent_grid"] != true
          name(zone["grid"], x, y, width:, height:)
        elsif zone["use_parent_grid"] == true
          name(grid["background"], x, y, width:, height:)
        end

      format_zone(zone, inner)
    end

    # Zone locationFormat interpolates $name$ and $gridLocation$ (Zone.java);
    # default behaves like "$name$".
    def format_zone(zone, grid_location)
      format = zone["location_format"]
      if format.present?
        format.gsub("$name$", zone["name"].to_s).gsub("$gridLocation$", grid_location.to_s).presence
      else
        grid_location.presence || zone["name"].presence
      end
    end

    # Inverse of the hex lattice: raw column/row per HexGrid#getRawColumn /
    # getRawRow, then the same naming as the painted labels.
    def hex_cell_name(grid, x, y, width:, height:)
      numbering = grid["numbering"] or return nil
      dx = grid["dx"].to_f
      dy = grid["dy"].to_f
      return nil if dx <= 0 || dy <= 0

      sideways = grid["sideways"]
      px, py = sideways ? [ y, x ] : [ x, y ]
      px -= grid["x0"].to_i
      py -= grid["y0"].to_i

      raw_col = (px / dx + 0.5).floor
      raw_row =
        if ((px / dx).round % 2).zero?
          (py / dy).round
        else
          ((py - dy / 2) / dy).round
        end

      maxes = GridNumbering.max_indices(grid, width, height)
      GridNumbering.hex_name(numbering, raw_col, raw_row, sideways, maxes)
    end

    def square_cell_name(grid, x, y, width:, height:)
      numbering = grid["numbering"] or return nil
      dx = grid["dx"].to_f
      dy = grid["dy"].to_f
      return nil if dx <= 0 || dy <= 0

      col = ((x - grid["x0"].to_i) / dx).round
      row = ((y - grid["y0"].to_i) / dy).round
      col = (width / dx + 0.5).floor - col if numbering["hDescend"] == "true"
      row = (height / dy + 0.5).floor - row if numbering["vDescend"] == "true"
      GridNumbering.cell_name(numbering, row, col)
    end

    def region_name(grid, x, y)
      regions = (grid["regions"] || []).select { |r| r["x"] && r["y"] }
      regions.min_by { |r| (r["x"] - x)**2 + (r["y"] - y)**2 }&.dig("name")
    end

    # Inverse of #name: the board-local [x, y] for a location name, or nil.
    # Regions are looked up directly; hex/square cells (and zoned grids through
    # their background grid) are matched by re-running the forward naming on
    # each candidate cell centre, so every quirk — descending, stagger, zone
    # locationFormat — is honoured without re-deriving its inverse. Only runs on
    # explicit "send to location" commands, so the linear scan is acceptable.
    def point_for(grid, location, width:, height:)
      return nil unless grid.is_a?(Hash) && location.present?

      case grid["type"]
      when "region" then region_point(grid, location)
      when "zoned" then zoned_point(grid, location, width:, height:)
      when "hex", "square" then cell_point(grid, location, width:, height:)
      end
    end

    def region_point(grid, location)
      r = (grid["regions"] || []).find { |region| region["name"] == location && region["x"] && region["y"] }
      [ r["x"], r["y"] ] if r
    end

    def zoned_point(grid, location, width:, height:)
      zones = grid["zones"] || []

      # Zones addressed by their own name (locationFormat "$name$") resolve to
      # the zone centroid — cheap, no lattice scan.
      named = zones.find { |z| z["path"].present? && format_zone(z, nil) == location }
      return centroid(named["path"]) if named

      # Otherwise a grid location inside some zone: scan each grid-bearing zone's
      # cell centres (clipped to the zone) and name them through that zone, the
      # inverse of #zoned_name.
      zones.each do |zone|
        path = zone["path"]
        next if path.blank?
        inner = zone["use_parent_grid"] == true ? grid["background"] : zone["grid"]
        next unless inner.is_a?(Hash)

        point = cell_centers(inner, width, height, bounds: bbox(path)).find do |x, y|
          GridSnap.contains?(path, x, y) &&
            format_zone(zone, name(inner, x, y, width:, height:)) == location
        end
        return point if point
      end
      nil
    end

    def cell_point(grid, location, width:, height:)
      cell_centers(grid, width, height).find { |x, y| name(grid, x, y, width:, height:) == location }
    end

    # Cell centres of a hex/square grid, mirroring GridNumbering's lattice
    # (columns every dx, hex odd columns shifted dy/2) so each centre maps to a
    # named cell. bounds [x0, y0, x1, y1] clips the scan to a region (default
    # the whole board). Returns an enumerator of [x, y] in board coordinates.
    def cell_centers(grid, width, height, bounds: nil)
      return enum_for(:cell_centers, grid, width, height, bounds:) unless block_given?

      dx = grid["dx"].to_f
      dy = grid["dy"].to_f
      return if dx <= 0 || dy <= 0
      x0 = grid["x0"].to_i
      y0 = grid["y0"].to_i
      hex = grid["type"] == "hex"
      sideways = hex && grid["sideways"]
      bx0, by0, bx1, by1 = bounds || [ 0, 0, width, height ]
      # Iterate in the lattice's own (rotated, when sideways) space: the column
      # axis runs along px, rows along py.
      px0, py0, px1, py1 = sideways ? [ by0, bx0, by1, bx1 ] : [ bx0, by0, bx1, by1 ]

      ((px0 - dx - x0) / dx).floor.upto(((px1 + dx - x0) / dx).ceil) do |c|
        cx = x0 + c * dx
        offset = hex && c.odd? ? dy / 2.0 : 0.0
        ((py0 - dy - y0) / dy).floor.upto(((py1 + dy - y0) / dy).ceil) do |r|
          cy = y0 + offset + r * dy
          x, y = sideways ? [ cy, cx ] : [ cx, cy ]
          yield [ x.round, y.round ] if x.between?(bx0, bx1) && y.between?(by0, by1)
        end
      end
    end

    def bbox(path)
      xs = path.map { |p| p[0] }
      ys = path.map { |p| p[1] }
      [ xs.min, ys.min, xs.max, ys.max ]
    end

    def centroid(path)
      xs = path.map { |p| p[0] }
      ys = path.map { |p| p[1] }
      [ (xs.sum / path.size.to_f).round, (ys.sum / path.size.to_f).round ]
    end
  end
end
