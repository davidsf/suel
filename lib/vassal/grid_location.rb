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
  end
end
