module Vassal
  # Decodes a deobfuscated savedGame stream: one recursively ESC-separated
  # command string (GameModule.java COMMAND_SEPARATOR = 27). Leaves are
  # BasicCommandEncoder commands ("+/", "-/", "D/", "M/", "begin_save"...).
  module Commands
    SEPARATOR = 27.chr.freeze

    AddPiece = Struct.new(:id, :type, :state, keyword_init: true)
    MovePiece = Struct.new(:id, :map_id, :x, :y, keyword_init: true)

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
      end
    end
  end
end
