module Vassal
  # Exact port of VASSAL.tools.SequenceEncoder: encodes a sequence of strings
  # into one string with a delimiter, escaping the delimiter with a backslash.
  # A backslash escapes ONLY an immediately following delimiter; tokens wrapped
  # in single quotes are unwrapped after assembly (added by the encoder when a
  # value starts with a backslash or is already quote-wrapped).
  class SequenceEncoder
    def initialize(delimiter, value = nil)
      @delim = delimiter
      @buffer = nil
      append(value) unless value.nil?
    end

    def append(value)
      if @buffer.nil?
        @buffer = +""
      else
        @buffer << @delim
      end

      value = value.to_s
      return self if value.empty?

      if value.start_with?("\\") || (value.start_with?("'") && value.end_with?("'") && value.length > 1)
        @buffer << "'"
        append_escaped(value)
        @buffer << "'"
      else
        append_escaped(value)
      end
      self
    end

    def value
      @buffer
    end

    private

    def append_escaped(value)
      value.each_char do |c|
        @buffer << "\\" if c == @delim
        @buffer << c
      end
    end

    # Port of SequenceEncoder.Decoder (SequenceEncoder.java:211-311).
    class Decoder
      include Enumerable

      def initialize(value, delimiter)
        @val = value
        @delim = delimiter
        @start = 0
        @stop = value ? value.length : 0
      end

      def more_tokens?
        !@val.nil?
      end

      NO_DEFAULT = Object.new
      private_constant :NO_DEFAULT

      def next_token(default = NO_DEFAULT)
        unless more_tokens?
          raise ParseError, "no more tokens" if default.equal?(NO_DEFAULT)
          return default
        end

        if @start == @stop
          # token for "null" is the empty string
          @val = nil
          return ""
        end

        # Jump between delimiter occurrences with String#index instead of
        # scanning char by char (pieces nest deeply; a linear scan per level
        # turns quadratic on real modules).
        buf = nil
        tok = nil
        search = @start
        loop do
          i = @val.index(@delim, search)
          if i.nil? || i >= @stop
            # reached the end without a real delimiter
            if buf.nil? || buf.empty?
              tok = @val[@start...@stop]
            else
              buf << @val[@start...@stop]
            end
            @val = nil
            break
          end

          if i > 0 && @val[i - 1] == "\\"
            # escaped delimiter; piece together the token
            buf ||= +""
            buf << @val[@start...(i - 1)]
            @start = i
            search = i + 1
          else
            # real delimiter
            if buf.nil? || buf.empty?
              tok = @val[@start...i]
            else
              buf << @val[@start...i]
            end
            @start = i + 1
            break
          end
        end

        unquote(tok || buf || "")
      end

      def next_int(default)
        more_tokens? ? Integer(next_token) : default
      rescue ArgumentError
        default
      end

      def next_double(default)
        more_tokens? ? Float(next_token) : default
      rescue ArgumentError
        default
      end

      def next_boolean(default)
        more_tokens? ? next_token == "true" : default
      end

      # Port of nextStringArray + StringArrayConfigurer.stringToArray:
      # the next token is itself a ','-delimited sequence.
      def next_string_array(min_length = 0)
        items = []
        if more_tokens?
          sub = Decoder.new(next_token, ",")
          items << sub.next_token while sub.more_tokens?
        end
        items << "" while items.length < min_length
        items
      end

      def remaining
        more_tokens? ? @val[@start...@stop] : ""
      end

      def each
        yield next_token while more_tokens?
      end

      private

      def unquote(token)
        if token.length > 1 && token.start_with?("'") && token.end_with?("'")
          token[1..-2]
        else
          token
        end
      end
    end
  end
end
