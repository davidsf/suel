module Vassal
  # Hex/square grid cell labels ("1015", "A12"...), ported from VASSAL's
  # RegularGridNumbering / HexGridNumbering — including its quirks (doubled
  # letters AA/BB for alphabetic overflow, maxRows = height/dx) so descending
  # and staggered modules match the desktop app.
  module GridNumbering
    ALPHABET = ("A".."Z").to_a.freeze
    MAX_LABELS = 15_000

    module_function

    # Returns [{x:, y:, text:}, ...] in board coordinates, or [] when the grid
    # has no numbering or would produce an absurd amount of labels.
    def labels(grid, width, height)
      return [] unless grid.is_a?(Hash) && width.to_i.positive?

      grid = grid["background"] if grid["type"] == "zoned"
      return [] unless grid.is_a?(Hash) && grid["numbering"].is_a?(Hash)

      case grid["type"]
      when "hex" then hex_labels(grid, width, height)
      when "square" then square_labels(grid, width, height)
      else []
      end
    end

    def hex_labels(grid, width, height)
      dx = grid["dx"].to_f
      dy = grid["dy"].to_f
      return [] if dx <= 0 || dy <= 0

      sideways = grid["sideways"]
      x0 = grid["x0"].to_i
      y0 = grid["y0"].to_i
      # Iterate the raw lattice in rotated space (columns every dx, rows every
      # dy with odd columns shifted dy/2), like HexGrid#getRawColumn/getRawRow.
      rot_w, rot_h = sideways ? [ height, width ] : [ width, height ]
      cols = (rot_w / dx).ceil + 1
      rows = (rot_h / dy).ceil + 1
      return [] if cols * rows > MAX_LABELS

      numbering = grid["numbering"]
      maxes = max_indices(grid, width, height)
      result = []
      (-1..cols).each do |c|
        cx = x0 + c * dx
        next if cx < -dx || cx > rot_w + dx
        offset = c.odd? ? dy / 2.0 : 0.0
        (-1..rows).each do |r|
          cy = y0 + offset + r * dy
          next if cy < -dy || cy > rot_h + dy

          x, y = sideways ? [ cy, cx ] : [ cx, cy ]
          next if x.negative? || y.negative? || x > width || y > height

          result << {
            x: x.round, y: (y - (sideways ? dx : dy) * 0.3).round,
            text: hex_name(numbering, c, r, sideways, maxes)
          }
        end
      end
      result
    end

    def square_labels(grid, width, height)
      dx = grid["dx"].to_f
      dy = grid["dy"].to_f
      return [] if dx <= 0 || dy <= 0

      x0 = grid["x0"].to_i
      y0 = grid["y0"].to_i
      cols = (width / dx).ceil + 1
      rows = (height / dy).ceil + 1
      return [] if cols * rows > MAX_LABELS

      numbering = grid["numbering"]
      max_cols = (width / dx + 0.5).floor
      max_rows = (height / dy + 0.5).floor
      result = []
      (0..cols).each do |c|
        x = x0 + c * dx
        next if x.negative? || x > width
        (0..rows).each do |r|
          y = y0 + r * dy
          next if y.negative? || y > height
          col = numbering["hDescend"] == "true" ? max_cols - c : c
          row = numbering["vDescend"] == "true" ? max_rows - r : r
          result << { x: x.round, y: (y - dy * 0.3).round, text: cell_name(numbering, row, col) }
        end
      end
      result
    end

    # HexGridNumbering#getColumn/getRow: descending flips against max indices
    # (computed with VASSAL's literal height/dx, width/dy), stagger shifts odd
    # raw columns one row.
    def hex_name(numbering, raw_col, raw_row, sideways, maxes)
      max_rows, max_cols = maxes
      col = raw_col
      row = raw_row

      col = max_rows - col if numbering["vDescend"] == "true" && sideways
      col = max_cols - col if numbering["hDescend"] == "true" && !sideways
      row = max_rows - row if numbering["vDescend"] == "true" && !sideways
      row = max_cols - row if numbering["hDescend"] == "true" && sideways

      if numbering["stagger"] == "true" && raw_col.odd?
        if sideways
          row += numbering["hDescend"] == "true" ? -1 : 1
        else
          row += numbering["vDescend"] == "true" ? -1 : 1
        end
      end

      cell_name(numbering, row, col)
    end

    def max_indices(grid, width, height)
      # Literal port of HexGridNumbering#getMaxRows/getMaxColumns
      [ (height / grid["dx"].to_f + 0.5).floor, (width / grid["dy"].to_f + 0.5).floor ]
    end

    def cell_name(numbering, row, col)
      row_name = index_name(row + numbering["vOff"].to_i, numbering["vType"], numbering["vLeading"].to_i)
      col_name = index_name(col + numbering["hOff"].to_i, numbering["hType"], numbering["hLeading"].to_i)
      sep = numbering["sep"].to_s
      numbering["first"] == "V" ? "#{row_name}#{sep}#{col_name}" : "#{col_name}#{sep}#{row_name}"
    end

    # RegularGridNumbering#getName(value, type, leading): alphabetic counts
    # A..Z then AA, BB, CC...; numeric pads with leading zeros.
    def index_name(value, type, leading)
      sign = value.negative? ? "-" : ""
      value = value.abs

      if type == "A"
        name = +""
        loop do
          name << ALPHABET[value % 26]
          value -= 26
          break if value.negative?
        end
        return sign + name
      end

      zeros = +""
      while leading.positive? && value < 10**leading
        zeros << "0"
        leading -= 1
      end
      "#{sign}#{zeros}#{value}"
    end
  end
end
