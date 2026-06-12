require "test_helper"

class Vassal::GridLocationTest < ActiveSupport::TestCase
  NUMBERING = {
    "hOff" => "1", "vOff" => "1", "hType" => "N", "vType" => "N",
    "hLeading" => "1", "vLeading" => "1", "sep" => "", "first" => "H",
    "stagger" => "false", "hDescend" => "false", "vDescend" => "false"
  }.freeze

  HEX = {
    "type" => "hex", "dx" => 60.0, "dy" => 52.0, "x0" => 30, "y0" => 26,
    "numbering" => NUMBERING
  }.freeze

  test "names hex cells like the painted labels" do
    assert_equal "0101", Vassal::GridLocation.name(HEX, 32, 28, width: 300, height: 200)
    assert_equal "0201", Vassal::GridLocation.name(HEX, 91, 53, width: 300, height: 200)
  end

  test "hex grids without numbering have no location name" do
    assert_nil Vassal::GridLocation.name(HEX.except("numbering"), 32, 28, width: 300, height: 200)
  end

  test "regions name by proximity" do
    grid = { "type" => "region", "regions" => [
      { "name" => "Turn 1", "x" => 100, "y" => 50 }, { "name" => "Turn 2", "x" => 200, "y" => 50 }
    ] }
    assert_equal "Turn 2", Vassal::GridLocation.name(grid, 180, 60, width: 300, height: 100)
  end

  test "zoned grids name through the containing zone" do
    zoned = {
      "type" => "zoned",
      "background" => HEX,
      "zones" => [
        { "name" => "Caja de turnos", "path" => [ [ 1000, 0 ], [ 1200, 0 ], [ 1200, 100 ], [ 1000, 100 ] ],
          "grid" => { "type" => "region", "regions" => [ { "name" => "T1", "x" => 1050, "y" => 50 } ] } },
        { "name" => "Reserva", "path" => [ [ 0, 1000 ], [ 100, 1000 ], [ 100, 1100 ], [ 0, 1100 ] ] }
      ]
    }
    assert_equal "T1", Vassal::GridLocation.name(zoned, 1040, 40, width: 2000, height: 2000)
    assert_equal "Reserva", Vassal::GridLocation.name(zoned, 50, 1050, width: 2000, height: 2000),
      "a zone without its own grid... names by zone"
    assert_equal "0101", Vassal::GridLocation.name(zoned, 32, 28, width: 2000, height: 2000),
      "outside zones falls back to the background grid"
  end

  test "zone locationFormat interpolates name and grid location" do
    zoned = {
      "type" => "zoned",
      "background" => HEX,
      "zones" => [
        { "name" => "Norte", "path" => [ [ 0, 0 ], [ 300, 0 ], [ 300, 200 ], [ 0, 200 ] ],
          "location_format" => "$name$ $gridLocation$", "use_parent_grid" => true }
      ]
    }
    assert_equal "Norte 0101", Vassal::GridLocation.name(zoned, 32, 28, width: 300, height: 200)
  end
end
