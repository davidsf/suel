require "test_helper"
require "turbo/broadcastable/test_helper"

# Moving a piece from one map to another — the web equivalent of dragging a
# piece between VASSAL's separate map windows.
class PieceRelocateTest < ActionDispatch::IntegrationTest
  include VmodTestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @game_module = create_two_map_module!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
    scenario = @game_module.scenarios.find_by(kind: "module_setup")
    @game = Game.create!(game_module: @game_module, scenario:, creator: users(:one), name: "T")
    @game.copy_scenario_pieces!
    @game.players.create!(user: users(:one), side: "Bando A")
    @main = @game_module.game_maps.find_by(name: "Main Map")
    @reinf = @game_module.game_maps.find_by(name: "Reinforcements")
    @piece = @game.game_pieces.find_by(game_map_id: @reinf.id)
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "a player moves an on-map piece to another map, snapped to its board" do
    sign_in_as users(:one)
    entry = @game.board_layout(@main).entries.first
    lx, ly = entry.board.snap_point(100 - entry.x, 200 - entry.y)
    expected = [ lx + entry.x, ly + entry.y ]

    patch relocate_game_piece_path(@game, @piece), params: { map: @main.id, x: 100, y: 200 }
    assert_response :success

    @piece.reload
    assert_equal @main.id, @piece.game_map_id
    assert_equal entry.board.id, @piece.board_id
    assert_equal expected, [ @piece.x, @piece.y ]
  end

  test "relocation removes the piece from the source map and appends it to the destination, then logs" do
    sign_in_as users(:one)
    assert_difference -> { @game.game_events.count }, 1 do
      assert_broadcasts_on(@game, :remove, :append) do
        patch relocate_game_piece_path(@game, @piece), params: { map: @main.id, x: 90, y: 90 }
      end
    end
  end

  test "a piece that is not on a map cannot be relocated" do
    sign_in_as users(:one)
    hand_piece = @game.game_pieces.create!(hand_side: "Bando A", name: "X", type_string: "x", traits: [])
    patch relocate_game_piece_path(@game, hand_piece), params: { map: @main.id, x: 10, y: 10 }
    assert_response :unprocessable_entity
  end

  test "a map outside the module is not a valid destination" do
    sign_in_as users(:one)
    patch relocate_game_piece_path(@game, @piece), params: { map: 0, x: 10, y: 10 }
    assert_response :not_found
  end

  test "a spectator cannot relocate pieces" do
    sign_in_as users(:two)
    patch relocate_game_piece_path(@game, @piece), params: { map: @main.id, x: 10, y: 10 }
    assert_response :forbidden
    assert_equal @reinf.id, @piece.reload.game_map_id
  end

  private

  # The relocation broadcasts (besides the piece's own replace and the log
  # append) include a remove of the piece and an append to the destination
  # map's pieces container, in that order.
  def assert_broadcasts_on(game, *kinds)
    captured = capture_turbo_stream_broadcasts(game) { yield }
    actions = captured.map { |frame| frame["action"] }
    kinds.each { |kind| assert_includes actions, kind.to_s, "expected a #{kind} broadcast" }
  end
end
