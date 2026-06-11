require "test_helper"

class Vassal::SequenceEncoderTest < ActiveSupport::TestCase
  def decode(value, delim)
    Vassal::SequenceEncoder::Decoder.new(value, delim).to_a
  end

  test "splits plain tokens" do
    assert_equal %w[a b c], decode("a;b;c", ";")
  end

  test "backslash escapes an immediately following delimiter" do
    assert_equal [ "a;b", "c" ], decode("a\\;b;c", ";")
  end

  test "backslash not followed by the delimiter is a literal backslash" do
    assert_equal [ "a\\b", "c" ], decode("a\\b;c", ";")
  end

  test "escaped delimiter at the end of a token" do
    assert_equal [ "a;", "b" ], decode("a\\;;b", ";")
  end

  test "single-quote wrapped tokens are unwrapped" do
    assert_equal [ "foo" ], decode("'foo'", ";")
    assert_equal [ "'" ], decode("'", ";"), "lone quote stays"
    assert_equal [ "" ], decode("''", ";")
  end

  test "trailing delimiter yields a final empty token" do
    assert_equal [ "a", "" ], decode("a;", ";")
  end

  test "empty string yields one empty token" do
    assert_equal [ "" ], decode("", ";")
  end

  test "consecutive delimiters yield empty tokens" do
    assert_equal [ "a", "", "b" ], decode("a;;b", ";")
  end

  test "nil value has no tokens" do
    decoder = Vassal::SequenceEncoder::Decoder.new(nil, ";")
    assert_not decoder.more_tokens?
    assert_equal "x", decoder.next_token("x")
    assert_raises(Vassal::ParseError) { decoder.next_token }
  end

  test "typed readers with defaults" do
    d = Vassal::SequenceEncoder::Decoder.new("5;x;true;1.5", ";")
    assert_equal 5, d.next_int(0)
    assert_equal 7, d.next_int(7), "non-numeric falls back to default"
    assert d.next_boolean(false)
    assert_in_delta 1.5, d.next_double(0.0)
    assert_equal 9, d.next_int(9), "exhausted falls back to default"
  end

  test "next_string_array decodes a comma sub-sequence with minimum length" do
    d = Vassal::SequenceEncoder::Decoder.new("a,b\\,c;rest", ";")
    assert_equal [ "a", "b,c" ], d.next_string_array
    d2 = Vassal::SequenceEncoder::Decoder.new("x", ";")
    assert_equal [ "x", "" ], d2.next_string_array(2)
  end

  test "round trip through the encoder" do
    values = [ "plain", "with;delim", "\\starts", "'quoted'", "", "a\tb" ]
    encoder = Vassal::SequenceEncoder.new(";")
    values.each { |v| encoder.append(v) }
    assert_equal values, decode(encoder.value, ";")
  end

  test "trailing backslash merges with the next token (faithful to VASSAL's own quirk)" do
    encoder = Vassal::SequenceEncoder.new(";").append("ends\\").append("x")
    assert_equal [ "ends;x" ], decode(encoder.value, ";")
  end

  test "nested encodings survive two levels" do
    inner = Vassal::SequenceEncoder.new(";")
    inner.append("img.png").append("name;with;semis")
    outer = Vassal::SequenceEncoder.new("\t")
    outer.append(inner.value).append("piece;;;a.png;B")

    outer_tokens = decode(outer.value, "\t")
    assert_equal 2, outer_tokens.length
    assert_equal [ "img.png", "name;with;semis" ], decode(outer_tokens[0], ";")
    assert_equal "piece;;;a.png;B", outer_tokens[1]
  end
end
