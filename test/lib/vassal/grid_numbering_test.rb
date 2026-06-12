require "test_helper"

class Vassal::GridNumberingTest < ActiveSupport::TestCase
  NUMBERING = {
    "hOff" => "1", "vOff" => "1", "hType" => "N", "vType" => "N",
    "hLeading" => "1", "vLeading" => "1", "sep" => "", "first" => "H",
    "stagger" => "false", "hDescend" => "false", "vDescend" => "false",
    "fontSize" => "12", "visible" => "true"
  }.freeze

  HEX = {
    "type" => "hex", "dx" => 60.0, "dy" => 52.0, "x0" => 30, "y0" => 26,
    "numbering" => NUMBERING
  }.freeze

  test "labels hex centers column-first with offsets and leading zeros" do
    labels = Vassal::GridNumbering.labels(HEX, 300, 200)
    by_text = labels.index_by { |l| l[:text] }

    assert by_text.key?("0101"), "raw (0,0) -> col 1 row 1"
    assert_equal 30, by_text["0101"][:x]
    assert by_text.key?("0201"), "odd column staggers down half a hex"
    assert_equal 90, by_text["0201"][:x]
  end

  test "alphabetic columns and V-first ordering" do
    numbering = NUMBERING.merge("hType" => "A", "hOff" => "0", "first" => "V", "sep" => "-")
    labels = Vassal::GridNumbering.labels(HEX.merge("numbering" => numbering), 300, 200)
    texts = labels.map { |l| l[:text] }

    assert_includes texts, "01-A", "row first, alphabetic column"
  end

  test "alphabetic overflow doubles letters like VASSAL" do
    assert_equal "A", Vassal::GridNumbering.index_name(0, "A", 0)
    assert_equal "Z", Vassal::GridNumbering.index_name(25, "A", 0)
    assert_equal "AA", Vassal::GridNumbering.index_name(26, "A", 0)
    assert_equal "BB", Vassal::GridNumbering.index_name(27, "A", 0)
  end

  test "numeric leading zeros" do
    assert_equal "005", Vassal::GridNumbering.index_name(5, "N", 2)
    assert_equal "15", Vassal::GridNumbering.index_name(15, "N", 1)
  end

  test "no numbering means no labels" do
    assert_empty Vassal::GridNumbering.labels(HEX.except("numbering"), 300, 200)
    assert_empty Vassal::GridNumbering.labels(nil, 300, 200)
  end

  test "zoned grids number from the background grid" do
    zoned = { "type" => "zoned", "background" => HEX, "zones" => [] }
    assert Vassal::GridNumbering.labels(zoned, 300, 200).any?
  end

  test "gives up beyond the label cap" do
    huge = HEX.merge("dx" => 2.0, "dy" => 2.0)
    assert_empty Vassal::GridNumbering.labels(huge, 10_000, 10_000)
  end
end
