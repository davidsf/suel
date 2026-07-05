require "test_helper"

class GlobalKeysControllerTest < ActionDispatch::IntegrationTest
  include VmodTestHelper

  setup do
    @game_module = create_setup_module!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
    @game = Game.create!(game_module: @game_module, creator: users(:one), name: "S",
                         scenario: @game_module.scenarios.find_by(kind: "module_setup"))
    @game.copy_scenario_pieces!
    @game.players.create!(user: users(:one), side: "GE")

    map = @game_module.game_maps.find_by(name: "Main Map")
    board = map.boards.first
    entry = @game.board_layout(map).entries.first
    @control = @game.game_pieces.create!(game_map: map, board:, x: entry.x + 500, y: entry.y + 350,
                                         z_order: 10, name: "Setup 1941 Scenario", type_string: "x",
                                         traits: setup_control_traits)
    @unit = @game.game_pieces.create!(game_map: map, board:, x: entry.x + 400, y: entry.y + 300,
                                      z_order: 11, name: "Unit", type_string: "x",
                                      traits: setup_unit_traits("0101"))
  end

  teardown { FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s)) }

  test "a player fires the setup button: units place and the log records it" do
    sign_in_as users(:one)
    before = [ @unit.x, @unit.y ]

    post game_global_keys_path(@game, button: 0)
    assert_response :ok
    refute_equal before, [ @unit.reload.x, @unit.reload.y ], "the unit moved to its scenario hex"
    assert_includes @game.game_events.last.body, "1941 Campaign"
  end

  test "spectators cannot fire global keys" do
    sign_in_as users(:two)
    post game_global_keys_path(@game, button: 0)
    assert_response :forbidden
  end

  test "an unknown button index is rejected" do
    sign_in_as users(:one)
    post game_global_keys_path(@game, button: 99)
    assert_response :unprocessable_entity
  end

  test "anonymous users are redirected to login" do
    post game_global_keys_path(@game, button: 0)
    assert_redirected_to new_session_path
  end
end
