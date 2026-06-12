require "test_helper"

class Vassal::CommandsTest < ActiveSupport::TestCase
  test "parses a BoardPicker board selection" do
    leaf = "MapBoardPicker\tScen-1 Map\t0\t0"
    setup = Vassal::Commands.parse_leaf(leaf)

    assert_instance_of Vassal::Commands::BoardSetup, setup
    assert_equal "Map", setup.map_id
    assert_equal [ { "name" => "Scen-1 Map", "col" => 0, "row" => 0, "reversed" => false } ], setup.boards
  end

  test "parses a multi-board reversed selection" do
    leaf = "EuropaBoardPicker\tNorth/rev\t0\t0\tSouth\t0\t1"
    setup = Vassal::Commands.parse_leaf(leaf)

    assert_equal "Europa", setup.map_id
    assert_equal 2, setup.boards.size
    assert setup.boards[0]["reversed"]
    assert_equal [ "South", 0, 1 ], setup.boards[1].values_at("name", "col", "row")
  end

  test "ignores unknown commands" do
    assert_nil Vassal::Commands.parse_leaf("LOG\tsomething")
    assert_nil Vassal::Commands.parse_leaf("begin_save")
  end
end
