require "test_helper"
require "turbo/broadcastable/test_helper"

class GamePiecesControllerTest < ActionDispatch::IntegrationTest
  include VmodTestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @game_module = GameModule.new
    @game_module.package.attach(io: file_fixture("mini.vmod").open, filename: "mini.vmod", content_type: "application/zip")
    @game_module.save!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload

    @game = Game.create!(game_module: @game_module, scenario: @game_module.scenarios.vsav.first,
                         creator: users(:one), name: "Prueba")
    @game.copy_scenario_pieces!
    @game.players.create!(user: users(:one), side: "Bando A")
    @piece = @game.game_pieces.first
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "a player can move a piece and the change is broadcast" do
    sign_in_as users(:one)

    assert_turbo_stream_broadcasts(@game, count: 1) do
      patch move_game_piece_path(@game, @piece), params: { x: 100, y: 200 }
    end
    assert_response :success
    assert_match "game_piece_#{@piece.id}", response.body
    assert_equal [ 100, 200 ], [ @piece.reload.x, @piece.y ]
  end

  test "an authenticated spectator cannot move pieces" do
    sign_in_as users(:two)
    patch move_game_piece_path(@game, @piece), params: { x: 1, y: 2 }
    assert_response :forbidden
    assert_not_equal 1, @piece.reload.x
  end

  test "anonymous users are redirected" do
    patch move_game_piece_path(@game, @piece), params: { x: 1, y: 2 }
    assert_redirected_to new_session_path
  end

  test "flip on a piece without mask trait returns 422" do
    sign_in_as users(:one)
    piece = @game.game_pieces.detect { |p| p.traits.none? { |t| t["kind"] == "mask" } }
    patch flip_game_piece_path(@game, piece)
    assert_response :unprocessable_entity
  end

  test "rotate steps the facing" do
    sign_in_as users(:one)
    piece = @game.game_pieces.detect { |p| p.traits.any? { |t| t["kind"] == "rotate" } }
    skip "fixture has no rotatable piece" unless piece

    patch rotate_game_piece_path(@game, piece), params: { direction: 1 }
    assert_response :success
  end
end
