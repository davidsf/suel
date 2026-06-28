require "test_helper"

class PiecesHelperTest < ActionView::TestCase
  def hit_traits(value)
    [
      { "kind" => "dynamic_property", "name" => "c", "numeric" => true, "value" => value.to_s },
      { "kind" => "label", "text" => "$c$", "vertical_pos" => "b", "horizontal_pos" => "l",
        "font_size" => 20, "fg" => "204,0,102", "bg" => "255,255,255" },
      { "kind" => "basic", "image" => "u.png", "name" => "Unit" }
    ]
  end

  test "a label resolves its $property$ references to the current value" do
    labels = piece_labels(hit_traits(3))
    assert_equal [ "3" ], labels.map { |l| l["resolved"] }
  end

  test "a counter label is hidden while it reads 0" do
    assert_empty piece_labels(hit_traits(0))
  end

  test "label style places the hit counter in the bottom-left with its colors" do
    label = piece_labels(hit_traits(2)).first
    style = piece_label_style(label)
    assert_includes style, "bottom:0"
    assert_includes style, "left:0"
    assert_includes style, "color:rgb(204,0,102)"
    assert_includes style, "background:rgb(255,255,255)"
    assert_includes style, "transform:none"
  end

  test "unknown property tokens are left untouched" do
    traits = [ { "kind" => "label", "text" => "$pieceName$ x$missing$" },
               { "kind" => "basic", "name" => "Cohort" } ]
    assert_equal [ "Cohort x$missing$" ], piece_labels(traits).map { |l| l["resolved"] }
  end
end
