require "test_helper"

class Vassal::PropertyExpressionTest < ActiveSupport::TestCase
  def match?(expr, props = {})
    Vassal::PropertyExpression.match?(expr, props)
  end

  test "evaluates a numeric comparison against a property" do
    assert match?("{$Count$==0}", "Count" => "0")
    refute match?("{$Count$==0}", "Count" => "3")
    assert match?("{$Count$>2}", "Count" => "3")
    assert match?("{$Count$<=3}", "Count" => "3")
  end

  test "evaluates string equality and inequality" do
    assert match?("{$Side$==\"GE\"}", "Side" => "GE")
    assert match?("{$Side$!=\"AL\"}", "Side" => "GE")
  end

  test "combines comparisons with && and ||" do
    props = { "A" => "1", "B" => "2" }
    assert match?("{$A$==1 && $B$==2}", props)
    refute match?("{$A$==1 && $B$==9}", props)
    assert match?("{$A$==9 || $B$==2}", props)
  end

  test "an unknown property declines to a confident false" do
    refute match?("{$Missing$==0}", {}), "never restrict on a property we do not know"
  end

  test "blank or unparseable expressions are false" do
    refute match?("", {})
    refute match?("{garbage}", {})
  end

  test "a bare identifier resolves as a property when it exists" do
    assert match?('{BasicName=="Setup 1941 Scenario"}', "BasicName" => "Setup 1941 Scenario")
    refute match?('{BasicName=="Setup 1941 Scenario"}', "BasicName" => "Other")
  end

  test "an unknown bare token stays a literal" do
    assert match?("{$Count$==3}", "Count" => "3"), "numeric literals keep working"
    assert match?('{"GE"=="GE"}', {})
  end
end
