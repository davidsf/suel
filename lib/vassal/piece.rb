module Vassal
  # Decoding of serialized game pieces: the text content of a PieceSlot /
  # CardSlot / PrototypeDefinition is an AddPiece command "+/id/TYPE/STATE"
  # where TYPE and STATE are tab-delimited stacks of decorator traits
  # (outermost first) ending with the BasicPiece.
  module Piece
    TAB = "\t".freeze

    # Splits a TYPE or STATE string into per-trait tokens, outermost first.
    #
    # The encoding is recursive, not flat (Decorator.getType): each decorator
    # appends the WHOLE inner piece string as a single escaped token, so we
    # peel one [trait, rest] pair per level like BasicCommandEncoder#createPiece.
    def self.split_traits(string)
      tokens = []
      while string
        decoder = SequenceEncoder::Decoder.new(string, TAB)
        tokens << decoder.next_token
        string = decoder.more_tokens? ? decoder.next_token : nil
      end
      tokens
    end

    # Inverse of split_traits: rebuilds the recursive pair encoding.
    def self.join_traits(tokens)
      return "" if tokens.empty?
      tokens.reverse.reduce(nil) do |inner, token|
        inner.nil? ? token : SequenceEncoder.new(TAB, token).append(inner).value
      end
    end

    # Parses an expanded piece into a list of trait hashes ready for JSON
    # storage, outermost first. Never raises: unparseable traits come back as
    # kind "unknown".
    def self.parse_traits(type_string, state_string)
      types = split_traits(type_string.to_s)
      states = split_traits(state_string.to_s)
      types.each_with_index.map do |type, i|
        TraitRegistry.parse(type, states[i])
      end
    end
  end
end
