require "test_helper"

# The VASSAL command bus end to end: revealing a hidden-unit marker. Firing the
# marker's "Reveal" should record its location, draw a real unit from the deck
# onto that location, remove the marker, and log the reveal.
class PieceCommandTest < ActiveSupport::TestCase
  include VmodTestHelper

  REVEAL = "key:70,130".freeze

  setup do
    @game_module = create_reveal_module!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
    @scenario = @game_module.scenarios.find_by(kind: "module_setup")
    @game = Game.create!(game_module: @game_module, scenario: @scenario, creator: users(:one), name: "R")
    @map = @game_module.game_maps.find_by(name: "Main Map")
    @board = @map.boards.first
    @deck = @game_module.decks.find_by(name: "Hidden")

    @entry = @game.board_layout(@map).entries.first
    @cell = [ @entry.x + 30, @entry.y + 20 ] # board-local (30,20) => location "0101"

    @marker = @game.game_pieces.create!(game_map: @map, board: @board, x: @cell[0], y: @cell[1],
                                        z_order: 1, name: "Marker", type_string: "x", traits: reveal_marker_traits)
    @unit = @game.game_pieces.create!(deck: @deck, deck_position: 0,
                                      name: "Real Unit", type_string: "x", traits: reveal_unit_traits)
  end

  teardown { FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s)) }

  test "the marker names the cell it sits on" do
    assert_equal "0101", @marker.location_name
  end

  test "Reveal records the marker location into the game property" do
    PieceCommand.run(@marker, REVEAL, by: "GE")
    assert_equal "0101", @game.reload.property("GEUnkLoc")
  end

  test "Reveal draws the deck unit onto the marker's location" do
    PieceCommand.run(@marker, REVEAL, by: "GE")
    @unit.reload
    assert @unit.on_map?, "the unit left the deck"
    assert_equal @map.id, @unit.game_map_id
    assert_equal @cell, [ @unit.x, @unit.y ], "placed where the marker stood"
  end

  test "Reveal removes the marker to its send-to point" do
    PieceCommand.run(@marker, REVEAL, by: "GE")
    @marker.reload
    assert @marker.on_map?
    refute_equal @cell, [ @marker.x, @marker.y ], "the marker moved off its cell"
  end

  test "Reveal reports the revelation and tracks placed pieces and source decks" do
    cmd = PieceCommand.run(@marker, REVEAL, by: "GE")
    assert_includes cmd.reports.join, "revealed"
    assert_equal [ @unit.id, @marker.id ].sort, cmd.touched.keys.sort
    assert_equal [ @unit.id ], cmd.placed.map(&:id), "the drawn unit is a newly placed piece"
    assert_equal [ @deck.id ], cmd.source_decks.map(&:id)
  end

  test "the relayed key is matched by name, not by physical code" do
    # The marker relays 57460,0,GEUnkPlacement; the unit triggers on
    # 57462,0,GEUnkPlacement — different codes, same name.
    PieceCommand.run(@marker, REVEAL, by: "GE")
    assert @unit.reload.on_map?
  end

  test "a Mark command places a marker counter on the unit's hex" do
    unit = @game.game_pieces.create!(game_map: @map, board: @board, x: @cell[0], y: @cell[1],
                                     z_order: 5, name: "Unit", type_string: "x", traits: marker_command_unit_traits)

    assert_difference -> { @game.game_pieces.count }, 1 do
      @cmd = PieceCommand.run(unit, "key:68,585", by: "GE")
    end
    marker = @game.game_pieces.find_by(name: "Status Marker")
    assert marker.on_map?
    assert_equal @cell, [ marker.x, marker.y ], "stamped on the unit's hex"
    assert_equal @map.id, marker.game_map_id
    assert marker.z_order > unit.z_order, "the marker sits on top"
    assert_equal [ marker.id ], @cmd.placed.map(&:id)
    assert_includes @cmd.reports.join, "marked"
  end

  test "PlaceMarker resolves the marker definition from its breadcrumb spec" do
    definition = @game_module.piece_definition_for_spec(STATUS_MARKER_SPEC)
    assert_equal "Status Marker", definition&.name
    assert_equal [ "Markers", "General" ], definition.palette_path
  end

  test "the marker exposes Reveal as a menu command" do
    assert_equal [ { "label" => "Reveal", "key" => REVEAL } ], @marker.menu_commands
  end

  test "a RestrictCommands trait hides Reveal while its expression holds" do
    restricted = reveal_marker_traits + [
      { "kind" => "restrict_commands", "action" => "Disable",
        "property_match" => "{$DeckCount$==0}", "keys" => [ REVEAL ] }
    ]
    @marker.update!(traits: restricted)

    assert_empty @marker.available_commands("DeckCount" => "0"), "hidden when the deck is empty"
    assert_equal [ "Reveal" ], @marker.available_commands("DeckCount" => "3").map { |c| c["label"] }
  end
end
