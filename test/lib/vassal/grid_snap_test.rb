require "test_helper"

class Vassal::GridSnapTest < ActiveSupport::TestCase
  HEX = { "type" => "hex", "dx" => 60.0, "dy" => 52.0, "x0" => 30, "y0" => 26, "snap" => true }.freeze

  test "snaps to the nearest even-column hex center" do
    # Even-lattice center at (30, 26); a nearby point lands there
    assert_equal [ 30, 26 ], Vassal::GridSnap.snap(HEX, 35, 30)
  end

  test "snaps to the nearest odd-column hex center" do
    # Odd columns are offset by (dx, dy/2): center at (90, 52)
    assert_equal [ 90, 52 ], Vassal::GridSnap.snap(HEX, 85, 49)
  end

  test "a point between two hexes goes to the closest one" do
    # x=60 is exactly between columns 30 and 90; y biases the choice
    x, y = Vassal::GridSnap.snap(HEX, 58, 28)
    assert_equal [ 30, 26 ], [ x, y ]
  end

  test "sideways grids swap axes around the same origin" do
    sideways = HEX.merge("sideways" => true)
    # In rotated space the point (y, x) snaps, then swaps back
    x, y = Vassal::GridSnap.snap(sideways, 30, 35)
    assert_equal [ 26, 30 ], [ x, y ]
  end

  test "respects snap disabled" do
    assert_equal [ 41, 47 ], Vassal::GridSnap.snap(HEX.merge("snap" => false), 41, 47)
  end

  test "edgesLegal snaps to hex side midpoints" do
    grid = { "type" => "hex", "dx" => 60.0, "dy" => 52.0, "x0" => 0, "y0" => 0,
             "snap" => true, "edges" => true }
    # Side midpoint between centers (0,0) and (60,26) is (30,13)
    assert_equal [ 30, 13 ], Vassal::GridSnap.snap(grid, 28, 12)
    # Near a center the center still wins
    assert_equal [ 0, 0 ], Vassal::GridSnap.snap(grid, 2, 1)
  end

  test "cornersLegal snaps to hex vertices" do
    grid = { "type" => "hex", "dx" => 60.0, "dy" => 52.0, "x0" => 0, "y0" => 0,
             "snap" => true, "corners" => true }
    # Vertex of the hex centered at origin: (20, 26)
    assert_equal [ 20, 26 ], Vassal::GridSnap.snap(grid, 22, 27)
  end

  test "edges and corners together pick the closest" do
    grid = { "type" => "hex", "dx" => 60.0, "dy" => 52.0, "x0" => 0, "y0" => 0,
             "snap" => true, "edges" => true, "corners" => true }
    assert_equal [ 30, 13 ], Vassal::GridSnap.snap(grid, 29, 13), "closer to the side midpoint"
    assert_equal [ 20, 26 ], Vassal::GridSnap.snap(grid, 21, 26), "closer to the vertex"
  end

  test "square grids snap to the lattice" do
    square = { "type" => "square", "dx" => 50.0, "dy" => 50.0, "x0" => 0, "y0" => 0 }
    assert_equal [ 100, 150 ], Vassal::GridSnap.snap(square, 110, 140)
  end

  test "zoned grids use the containing zone's grid, else the background" do
    zoned = {
      "type" => "zoned",
      "background" => HEX,
      "zones" => [
        { "name" => "Turn track", "path" => [ [ 1000, 0 ], [ 1200, 0 ], [ 1200, 200 ], [ 1000, 200 ] ],
          "grid" => { "type" => "region", "regions" => [ { "name" => "T1", "x" => 1050, "y" => 100 }, { "name" => "T2", "x" => 1150, "y" => 100 } ] } }
      ]
    }
    assert_equal [ 1050, 100 ], Vassal::GridSnap.snap(zoned, 1040, 90), "inside the zone snaps to its region"
    assert_equal [ 30, 26 ], Vassal::GridSnap.snap(zoned, 35, 30), "outside zones uses the background hex grid"
  end

  test "no grid means no snapping" do
    assert_equal [ 7, 9 ], Vassal::GridSnap.snap(nil, 7, 9)
    assert_equal [ 7, 9 ], Vassal::GridSnap.snap({ "type" => "unknown" }, 7, 9)
  end
end
