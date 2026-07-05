require "test_helper"

module Vassal
  class GlobalCommandTargetTest < ActiveSupport::TestCase
    test "decodes Empire of the Sun's setup-button target" do
      target = GlobalCommandTarget.parse(
        'MODULE|false|MAP|Empire of the Sun||||0|0||true|{"BasicName"}|{"Setup 1941 Scenario"}|EQUALS||'
      )
      assert_equal "MODULE", target.gkc_type
      assert_not target.fast_match_location?, "location fields only apply when fastMatchLocation is true"
      assert_equal "MAP", target.target_type
      assert_equal "Empire of the Sun", target.map
      assert target.fast_match_property?
      assert_equal "BasicName", target.property
      assert_equal "Setup 1941 Scenario", target.value
      assert_equal "EQUALS", target.compare
      assert_not target.deck_target?
    end

    test "decodes the counter-broadcast target" do
      target = GlobalCommandTarget.parse("COUNTER|false|MAP|||||0|0||false|||EQUALS||")
      assert_equal "COUNTER", target.gkc_type
      assert_not target.fast_match_location?
      assert_not target.fast_match_property?
      assert target.property_match?({}), "no property fast-match means every piece passes"
    end

    test "blank string parses to nil" do
      assert_nil GlobalCommandTarget.parse(nil)
      assert_nil GlobalCommandTarget.parse("")
    end

    test "property_match? compare modes" do
      base = 'MODULE|false|MAP|||||0|0||true|{"Power"}|%s|%s||'

      equals = GlobalCommandTarget.parse(format(base, '{"5"}', "EQUALS"))
      assert equals.property_match?({ "Power" => "5" })
      assert_not equals.property_match?({ "Power" => "6" })
      assert_not equals.property_match?({}), "missing property is not equal"

      not_equals = GlobalCommandTarget.parse(format(base, '{"5"}', "NOT_EQUALS"))
      assert not_equals.property_match?({ "Power" => "6" })
      assert not_equals.property_match?({}), "missing property is not-equal, VASSAL-style"

      greater = GlobalCommandTarget.parse(format(base, '{"5"}', "GREATER"))
      assert greater.property_match?({ "Power" => "10" }), "numeric compare when both sides are numbers"
      assert_not greater.property_match?({ "Power" => "3" })
      assert_not greater.property_match?({}), "missing property fails ordered compares"

      lexical = GlobalCommandTarget.parse(format(base, '{"b"}', "GREATER"))
      assert lexical.property_match?({ "Power" => "c" })
      assert_not lexical.property_match?({ "Power" => "a" })

      match = GlobalCommandTarget.parse(format(base, '{"Set.*"}', "MATCH"))
      assert match.property_match?({ "Power" => "Setup" })
      assert_not match.property_match?({ "Power" => "A Setup" }), "MATCH is a full-string regex"
    end

    test "deck targets are only DECK fast-match locations" do
      deck = GlobalCommandTarget.parse('MODULE|true|DECK|||||0|0|{"Mazo"}|false|||EQUALS||')
      assert deck.deck_target?
      assert_equal "Mazo", deck.deck
    end
  end
end
