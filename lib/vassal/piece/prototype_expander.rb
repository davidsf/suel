module Vassal
  module Piece
    # Replaces "prototype;Name" traits with the referenced prototype's trait
    # chain (recursively), mirroring VASSAL.counters.UsePrototype. Prototype
    # definitions are full pieces, so their trailing placeholder BasicPiece is
    # dropped when splicing.
    class PrototypeExpander
      # prototypes: { name => definition text ("+/null/TYPE/STATE") }
      def initialize(prototypes)
        @prototypes = prototypes
        @cache = {}
        @warnings = []
      end

      attr_reader :warnings

      # Returns [expanded_type_string, expanded_state_string]
      def expand(type_string, state_string)
        types, states = expand_tokens(Piece.split_traits(type_string), Piece.split_traits(state_string), [])
        [ join(types), join(states) ]
      end

      private

      def expand_tokens(types, states, seen)
        out_types = []
        out_states = []
        types.each_with_index do |type, i|
          state = states[i] || ""
          unless type.start_with?("prototype;")
            out_types << type
            out_states << state
            next
          end

          name = SequenceEncoder::Decoder.new(type.delete_prefix("prototype;"), ";").next_token("")
          if seen.include?(name)
            warn_once "ciclo de prototipos: #{name}"
            next
          end

          proto_types, proto_states = prototype_tokens(name)
          if proto_types.nil?
            warn_once "prototipo no encontrado: #{name}"
            next
          end

          expanded_types, expanded_states = expand_tokens(proto_types, proto_states, seen + [ name ])
          out_types.concat(expanded_types)
          out_states.concat(expanded_states)
        end
        [ out_types, out_states ]
      end

      def join(tokens)
        Piece.join_traits(tokens)
      end

      # The prototype's trait tokens, without its trailing BasicPiece.
      def prototype_tokens(name)
        @cache[name] ||= begin
          definition = @prototypes[name] or return nil
          command = AddCommand.parse(definition)
          types = Piece.split_traits(command.type)
          states = Piece.split_traits(command.state)
          types.pop if types.last&.start_with?("piece;")
          states.pop if states.length > types.length
          [ types, states ]
        end
      rescue ParseError
        warn_once "prototipo ilegible: #{name}"
        nil
      end

      def warn_once(message)
        @warnings << message unless @warnings.include?(message)
      end
    end
  end
end
