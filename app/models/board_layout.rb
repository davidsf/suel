# Pixel positions of the boards a scenario uses on a map, per the .vsav
# BoardPicker selection (VASSAL Map#setBoardBoundaries: column widths and row
# heights accumulate, everything shifted by the map's edge buffer). Falls back
# to the map's first board when the scenario carries no selection.
class BoardLayout
  Entry = Struct.new(:board, :x, :y, :reversed, keyword_init: true) do
    def width = board.width.to_i
    def height = board.height.to_i

    def contains?(px, py)
      width.positive? && px >= x && px < x + width && py >= y && py < y + height
    end
  end

  def initialize(game_map, setup_entries)
    @game_map = game_map
    @setup_entries = setup_entries || []
  end

  def entries
    @entries ||= build_entries
  end

  def width = entries.map { |e| e.x + e.width }.max.to_i
  def height = entries.map { |e| e.y + e.height }.max.to_i

  def entry_for(name) = entries.find { |e| e.board.name == name }

  def entry_at(x, y)
    entries.find { |e| e.contains?(x, y) } || entries.first
  end

  private

  def build_entries
    edge_x, edge_y = edge_buffer
    boards_by_name = @game_map.boards.index_by(&:name)
    selected = @setup_entries.filter_map do |entry|
      board = boards_by_name[entry["name"]] or next
      entry.merge("board" => board)
    end

    if selected.empty?
      board = @game_map.boards.first
      return board ? [ Entry.new(board:, x: edge_x, y: edge_y, reversed: false) ] : []
    end

    widths = Hash.new(0)
    heights = Hash.new(0)
    selected.each do |entry|
      widths[[ entry["col"], entry["row"] ]] = entry["board"].width.to_i
      heights[[ entry["col"], entry["row"] ]] = entry["board"].height.to_i
    end

    selected.map do |entry|
      col = entry["col"].to_i
      row = entry["row"].to_i
      x = edge_x + (0...col).sum { |c| widths[[ c, row ]] }
      y = edge_y + (0...row).sum { |r| heights[[ col, r ]] }
      Entry.new(board: entry["board"], x:, y:, reversed: entry["reversed"])
    end
  end

  def edge_buffer
    settings = @game_map.settings || {}
    [ settings["edgeWidth"].to_i, settings["edgeHeight"].to_i ]
  end
end
