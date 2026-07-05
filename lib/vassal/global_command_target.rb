module Vassal
  # Port of GlobalCommandTarget (GlobalCommandTarget.java#decode): the "Fast
  # Match" descriptor a Global Key Command uses to pre-select target pieces
  # before its BeanShell filter runs. A '|'-delimited SequenceEncoder string:
  #
  #   gkcType|fastMatchLocation|targetType|targetMap|targetBoard|targetZone|
  #   targetLocation|targetX|targetY|targetDeck|fastMatchProperty|
  #   targetProperty|targetValue|targetCompare|targetAttachment|targetAttachmentId
  #
  # Location fields (targetMap...) only apply when fastMatchLocation is true —
  # GlobalCommand.java#apply ignores them otherwise, so a target like
  # "MODULE|false|MAP|Empire of the Sun|..." searches every map.
  class GlobalCommandTarget
    COMPARE_MODES = %w[EQUALS NOT_EQUALS GREATER GREATER_EQUALS LESS LESS_EQUALS MATCH NOT_MATCH].freeze

    attr_reader :gkc_type, :target_type, :map, :board, :zone, :location,
                :deck, :property, :value, :compare

    def self.parse(string)
      new(string) if string.present?
    end

    def initialize(string)
      st = SequenceEncoder::Decoder.new(string, "|")
      @gkc_type = enum(st.next_token(""), "MAP")
      @fast_match_location = st.next_boolean(false)
      @target_type = enum(st.next_token("MAP"), "MAP")
      @map = unwrap(st.next_token(""))
      @board = unwrap(st.next_token(""))
      @zone = unwrap(st.next_token(""))
      @location = unwrap(st.next_token(""))
      st.next_token("0") # targetX
      st.next_token("0") # targetY
      @deck = unwrap(st.next_token(""))
      @fast_match_property = st.next_boolean(false)
      @property = unwrap(st.next_token(""))
      @value = unwrap(st.next_token(""))
      @compare = enum(st.next_token("EQUALS"), "EQUALS")
      @compare = "EQUALS" unless COMPARE_MODES.include?(@compare)
    end

    def fast_match_location? = @fast_match_location
    def fast_match_property? = @fast_match_property && property.present?
    def deck_target? = fast_match_location? && target_type == "DECK"

    # Port of GlobalCommand#passesPropertyFastMatch: compares the piece's
    # property against the target value per the compare mode. EQUALS is
    # null-safe; MATCH is a full-string regex; ordered compares are numeric
    # when both sides are, lexical otherwise.
    def property_match?(properties)
      return true unless fast_match_property?

      actual = properties[property]&.to_s
      case compare
      when "EQUALS" then value == actual
      when "NOT_EQUALS" then value != actual
      else
        return false if actual.nil?
        case compare
        when "MATCH" then full_match?(actual)
        when "NOT_MATCH" then !full_match?(actual)
        else ordered_match?(actual)
        end
      end
    end

    private

    def enum(token, default) = token.to_s.empty? ? default : token

    # A BeanShell string literal ({"Setup 1941 Scenario"}) evaluates to its
    # contents; other expressions are kept as-is (we can't evaluate BeanShell).
    def unwrap(expression)
      expression =~ /\A\{\s*"(.*)"\s*\}\z/m ? $1 : expression
    end

    def full_match?(actual)
      Regexp.new("\\A(?:#{value})\\z").match?(actual)
    rescue RegexpError
      false
    end

    def ordered_match?(actual)
      left, right =
        if numeric?(value) && numeric?(actual)
          [ Float(actual), Float(value) ]
        else
          [ actual, value ]
        end
      case compare
      when "GREATER" then left > right
      when "GREATER_EQUALS" then left >= right
      when "LESS" then left < right
      when "LESS_EQUALS" then left <= right
      else false
      end
    end

    def numeric?(string)
      Float(string)
      true
    rescue ArgumentError, TypeError
      false
    end
  end
end
