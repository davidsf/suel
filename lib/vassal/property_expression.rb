module Vassal
  # Evaluates a VASSAL property-match expression against a property hash, the
  # subset needed to gate menu commands (RestrictCommands). Handles BeanShell-
  # style "{ ... }" expressions and the legacy "prop=value" form, combining
  # comparisons with && / ||. Anything it cannot evaluate confidently —
  # unsupported syntax, or an unknown property — yields false, so a command is
  # only ever hidden on a comparison we are sure is true.
  module PropertyExpression
    module_function

    COMPARATORS = %w[== != >= <= > < =~ !~].freeze

    def match?(expression, properties)
      expression = expression.to_s.strip
      return false if expression.empty?

      body = expression.delete_prefix("{").delete_suffix("}").strip
      evaluate_or(body, properties)
    rescue StandardError
      false
    end

    def evaluate_or(body, props)
      split_top(body, "||").map { |part| evaluate_and(part, props) }.any?
    end

    def evaluate_and(body, props)
      split_top(body, "&&").map { |part| comparison(part.strip, props) }.all?
    end

    # A single "lhs OP rhs" comparison. Returns false on anything unevaluable.
    def comparison(text, props)
      comparator = COMPARATORS.find { |op| text.include?(op) } or return false
      lhs, rhs = text.split(comparator, 2)
      left = operand(lhs, props) or return false
      right = operand(rhs, props) or return false

      case comparator
      when "==" then left == right
      when "!=" then left != right
      when ">", "<", ">=", "<=" then numeric_compare(comparator, left, right)
      when "=~" then left.match?(Regexp.new(right))
      when "!~" then !left.match?(Regexp.new(right))
      end
    end

    # Resolves one side of a comparison to a string, or nil when it references an
    # unknown property (so the whole comparison declines to a confident false).
    def operand(token, props)
      token = token.strip
      if token.start_with?("$") && token.end_with?("$")
        props[token[1..-2]]&.to_s
      elsif token.start_with?('"') || token.start_with?("'")
        token[1..-2]
      else
        token
      end
    end

    def numeric_compare(comparator, left, right)
      left = Float(left, exception: false) or return false
      right = Float(right, exception: false) or return false
      left.public_send(comparator, right)
    end

    # Splits on a boolean operator at the top level (not inside quotes); good
    # enough for the flat expressions these restrictions use.
    def split_top(body, operator)
      body.split(operator)
    end
  end
end
