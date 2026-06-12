module Vassal
  # Decodes a deobfuscated savedGame stream: one recursively ESC-separated
  # command string (GameModule.java COMMAND_SEPARATOR = 27). Leaves are
  # BasicCommandEncoder commands ("+/", "-/", "D/", "M/", "begin_save"...).
  module Commands
    SEPARATOR = 27.chr.freeze

    AddPiece = Struct.new(:id, :type, :state, keyword_init: true)
    MovePiece = Struct.new(:id, :map_id, :x, :y, keyword_init: true)
    # Board selection for a map (BoardPicker#encode): which boards the save
    # uses and their grid cell (col, row) in the board mosaic.
    BoardSetup = Struct.new(:map_id, :boards, keyword_init: true)

    BOARD_PICKER = "BoardPicker".freeze

    # Yields each leaf command string, mirroring GameModule#decode recursion.
    def self.each_leaf(command, &block)
      return if command.nil? || command.empty?

      decoder = SequenceEncoder::Decoder.new(command, SEPARATOR)
      first = decoder.next_token
      if command == first
        yield first
      else
        each_leaf(first, &block)
        each_leaf(decoder.next_token, &block) while decoder.more_tokens?
      end
    end

    # Parses the leaves we understand into structs; other commands yield nil
    # (callers count them as unsupported, never as errors).
    def self.parse_leaf(leaf)
      if leaf.start_with?("+/")
        d = SequenceEncoder::Decoder.new(leaf[2..], "/")
        id = d.next_token
        AddPiece.new(id: id == "null" ? nil : id, type: d.next_token, state: d.next_token(""))
      elsif leaf.start_with?("M/")
        d = SequenceEncoder::Decoder.new(leaf[2..], "/")
        id = d.next_token
        map_id = d.next_token
        MovePiece.new(
          id: id == "null" ? nil : id,
          map_id: map_id == "null" ? nil : map_id,
          x: d.next_int(0), y: d.next_int(0)
        )
      else
        parse_board_setup(leaf)
      end
    end

    # "<mapId>BoardPicker\t<name[/rev]>\t<col>\t<row>..." (BoardPicker#encode)
    def self.parse_board_setup(leaf)
      d = SequenceEncoder::Decoder.new(leaf, "\t")
      head = d.next_token
      return nil unless head.end_with?(BOARD_PICKER)

      boards = []
      while d.more_tokens?
        name_part = SequenceEncoder::Decoder.new(d.next_token, "/")
        name = name_part.next_token
        reversed = name_part.more_tokens? && name_part.next_token == "rev"
        col = d.next_int(0)
        row = d.next_int(0)
        boards << { "name" => name, "col" => col, "row" => row, "reversed" => reversed }
      end
      BoardSetup.new(map_id: head.delete_suffix(BOARD_PICKER), boards: boards)
    end
  end
end
