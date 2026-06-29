require "test_helper"
require "turbo/broadcastable/test_helper"

# The pieces#command endpoint: a player fires a piece's "Reveal", and the result
# (drawn unit appended to the map, marker moved, log entry) is broadcast.
class PieceCommandControllerTest < ActionDispatch::IntegrationTest
  include VmodTestHelper
  include Turbo::Broadcastable::TestHelper

  REVEAL = "key:70,130".freeze

  setup do
    @game_module = create_reveal_module!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
    @game = Game.create!(game_module: @game_module, scenario: @game_module.scenarios.find_by(kind: "module_setup"),
                         creator: users(:one), name: "R")
    @game.players.create!(user: users(:one), side: "GE")
    @map = @game_module.game_maps.find_by(name: "Main Map")
    @board = @map.boards.first
    @deck = @game_module.decks.find_by(name: "Hidden")
    entry = @game.board_layout(@map).entries.first
    @cell = [ entry.x + 30, entry.y + 20 ]
    @marker = @game.game_pieces.create!(game_map: @map, board: @board, x: @cell[0], y: @cell[1],
                                        z_order: 1, name: "Marker", type_string: "x", traits: reveal_marker_traits)
    @unit = @game.game_pieces.create!(deck: @deck, deck_position: 0,
                                      name: "Real Unit", type_string: "x", traits: reveal_unit_traits)
  end

  teardown { FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s)) }

  test "a player reveals a marker and the unit is drawn onto the map" do
    sign_in_as users(:one)
    assert_difference -> { @game.game_events.count }, 1 do
      post command_game_piece_path(@game, @marker), params: { command: REVEAL }
    end
    assert_response :success
    assert @unit.reload.on_map?
    assert_equal @cell, [ @unit.x, @unit.y ]
  end

  test "a player marks a unit and the new marker is created on the map" do
    sign_in_as users(:one)
    unit = @game.game_pieces.create!(game_map: @map, board: @board, x: @cell[0], y: @cell[1],
                                     z_order: 5, name: "Unit", type_string: "x", traits: marker_command_unit_traits)

    assert_difference -> { @game.game_pieces.count }, 1 do
      post command_game_piece_path(@game, unit), params: { command: "key:68,585" }
    end
    assert_response :success
    marker = @game.game_pieces.find_by(name: "Status Marker")
    assert marker&.on_map?
    assert_equal @cell, [ marker.x, marker.y ]
  end

  test "a player removes a marker and it is deleted" do
    sign_in_as users(:one)
    marker = @game.game_pieces.create!(game_map: @map, board: @board, x: @cell[0], y: @cell[1],
                                       z_order: 9, name: "Disrupted Marker", type_string: "x", traits: lifecycle_marker_traits)

    assert_difference -> { @game.game_pieces.count }, -1 do
      post command_game_piece_path(@game, marker), params: { command: "key:68,130" }
    end
    assert_response :success
    assert_not GamePiece.exists?(marker.id)
  end

  test "an unknown keystroke the piece does not expose is rejected" do
    sign_in_as users(:one)
    post command_game_piece_path(@game, @marker), params: { command: "named:Bogus" }
    assert_response :forbidden
    assert @unit.reload.in_deck?, "nothing happened"
  end

  test "a spectator cannot run piece commands" do
    sign_in_as users(:two)
    post command_game_piece_path(@game, @marker), params: { command: REVEAL }
    assert_response :forbidden
    assert @unit.reload.in_deck?
  end
end
