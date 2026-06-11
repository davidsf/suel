module Vassal
  module Piece
    # An AddPiece command: "+/id/TYPE/STATE" (BasicCommandEncoder.java:323).
    # PieceSlot / PrototypeDefinition text content uses this same encoding.
    AddCommand = Struct.new(:id, :type, :state, keyword_init: true) do
      def self.parse(text)
        text = text.to_s.strip
        raise ParseError, "not an add-piece command" unless text.start_with?("+/")

        decoder = SequenceEncoder::Decoder.new(text[2..], "/")
        id = decoder.next_token
        new(
          id: id == "null" ? nil : id,
          type: decoder.next_token,
          state: decoder.more_tokens? ? decoder.next_token : ""
        )
      end
    end
  end
end
