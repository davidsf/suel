require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  include VmodTestHelper

  setup do
    @game_module = GameModule.new
    @game_module.package.attach(io: file_fixture("mini.vmod").open, filename: "mini.vmod", content_type: "application/zip")
    @game_module.save!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
    @scenario = @game_module.scenarios.vsav.first
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "anonymous users are redirected to login" do
    get games_path
    assert_redirected_to new_session_path
  end

  test "index shows a module card linking to its scenario picker frame" do
    sign_in_as users(:one)
    get games_path
    assert_response :success
    assert_select "a.card[href=?][data-turbo-frame=?]",
      game_module_scenarios_path(@game_module), "scenario-picker"
    assert_select "turbo-frame#scenario-picker"
  end

  test "create makes the game, copies pieces and seats the creator" do
    sign_in_as users(:one)
    assert_difference [ "Game.count", "Player.count" ], 1 do
      post games_path, params: { game: { scenario_id: @scenario.id, name: "Mi partida", side: "Bando A" } }
    end
    game = Game.last
    assert_redirected_to game_path(game)
    assert_equal @scenario.scenario_pieces.where.not(game_map_id: nil).count, game.game_pieces.count
    assert_equal "Bando A", game.players.first.side
  end

  test "join takes a free side and rejects an occupied one" do
    game = create_game!
    sign_in_as users(:two)

    post game_players_path(game, side: "Bando A")
    follow_redirect!
    assert_match "already taken", flash[:alert].to_s

    post game_players_path(game, side: "Bando B")
    assert_equal "Bando B", game.players.find_by(user: users(:two)).side
  end

  test "snap preview returns the snapped point and location" do
    game = create_game!
    sign_in_as users(:one)
    piece = game.game_pieces.where.not(game_map_id: nil).first

    get snap_game_path(game, map: piece.game_map_id, x: 500, y: 500)
    assert_response :success

    data = response.parsed_body
    entry = game.board_layout(piece.game_map).entry_at(500, 500)
    lx, ly = entry.board.snap_point(500 - entry.x, 500 - entry.y)
    assert_equal [ lx + entry.x, ly + entry.y ], [ data["x"], data["y"] ]
  end

  test "spectators can watch the table" do
    game = create_game!
    sign_in_as users(:two)
    get game_path(game)
    assert_response :success
    assert_match 'data-game-table-playable-value="false"', response.body
  end

  test "players get a playable table" do
    game = create_game!
    sign_in_as users(:one)
    get game_path(game)
    assert_response :success
    assert_match 'data-game-table-playable-value="true"', response.body
    assert_match "game_piece_", response.body
  end

  private

  def create_game!
    game = Game.create!(game_module: @game_module, scenario: @scenario,
                        creator: users(:one), name: "Prueba")
    game.copy_scenario_pieces!
    game.players.create!(user: users(:one), side: "Bando A")
    game
  end
end
