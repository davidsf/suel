require "test_helper"

class BoardLayoutTest < ActiveSupport::TestCase
  include VmodTestHelper

  setup do
    @game_module = create_game_module!
    ModuleImportJob.perform_now(@game_module)
    @map = @game_module.reload.game_maps.create!(
      name: "Mosaico", settings: { "identifier" => "Mosaico", "edgeWidth" => "10", "edgeHeight" => "20" }
    )
    @north = @map.boards.create!(name: "North", width: 1000, height: 800)
    @south = @map.boards.create!(name: "South", width: 1000, height: 600)
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "stacks selected boards by rows and columns with the edge buffer" do
    layout = BoardLayout.new(@map, [
      { "name" => "North", "col" => 0, "row" => 0, "reversed" => false },
      { "name" => "South", "col" => 0, "row" => 1, "reversed" => false }
    ])

    north = layout.entry_for("North")
    south = layout.entry_for("South")
    assert_equal [ 10, 20 ], [ north.x, north.y ]
    assert_equal [ 10, 820 ], [ south.x, south.y ], "row 1 sits below row 0's height"
    assert_equal 1010, layout.width
    assert_equal 1420, layout.height
  end

  test "picks the board containing a point" do
    layout = BoardLayout.new(@map, [
      { "name" => "North", "col" => 0, "row" => 0, "reversed" => false },
      { "name" => "South", "col" => 0, "row" => 1, "reversed" => false }
    ])

    assert_equal "North", layout.entry_at(500, 400).board.name
    assert_equal "South", layout.entry_at(500, 1000).board.name
  end

  test "falls back to the first board when there is no selection" do
    layout = BoardLayout.new(@map, nil)
    assert_equal [ "North" ], layout.entries.map { |e| e.board.name }
    assert_equal [ 10, 20 ], [ layout.entries.first.x, layout.entries.first.y ]
  end

  test "unknown board names fall back too" do
    layout = BoardLayout.new(@map, [ { "name" => "Nope", "col" => 0, "row" => 0 } ])
    assert_equal [ "North" ], layout.entries.map { |e| e.board.name }
  end
end
