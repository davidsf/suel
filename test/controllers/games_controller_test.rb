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

  test "the hand tray only exists when the module defines a PlayerHand" do
    sign_in_as users(:one)

    # Holland '44-style module: map windows but no PlayerHand.
    no_hands = create_two_map_module!
    ModuleImportJob.perform_now(no_hands)
    game = create_game_for!(no_hands.reload)
    get game_path(game)
    assert_response :success
    assert_no_match "hand-tray", response.body
    assert_no_match "hand_count", response.body

    # Card module: a "Mano A" PlayerHand owned by Bando A.
    with_hands = create_card_module!
    ModuleImportJob.perform_now(with_hands)
    game = create_game_for!(with_hands.reload)
    get game_path(game)
    assert_response :success
    assert_match "hand-tray-open", response.body
    assert_match "hand_count", response.body
  end

  test "a multi-board map prompts for a board at game creation and honors the choice" do
    sign_in_as users(:one)
    game_module = create_multi_board_module!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    scenario = game_module.scenarios.find_by(kind: "module_setup")
    map = game_module.game_maps.kind_map.first

    get new_game_path(scenario_id: scenario.id)
    assert_response :success
    assert_select "fieldset.board-choice legend", text: /Main Map/
    assert_select "input[type=radio][name=?][value=?]", "game[board_setup][#{map.identifier}]", "Small Map"

    post games_path, params: { game: { scenario_id: scenario.id, name: "Pacífico", side: "Bando A",
                                       board_setup: { map.identifier => "Small Map" } } }
    game = Game.last
    assert_redirected_to game_path(game)
    assert_equal "Small Map", game.board_layout(map).entries.first.board.name
    get game_path(game)
    assert_response :success
    assert_match "board2.png", response.body

    # An unknown board re-renders the form with the picker.
    post games_path, params: { game: { scenario_id: scenario.id, name: "Mal", side: "Bando A",
                                       board_setup: { map.identifier => "Nope" } } }
    assert_response :unprocessable_entity
    assert_select "fieldset.board-choice"
  end

  test "single-board modules show no board picker" do
    sign_in_as users(:one)
    get new_game_path(scenario_id: @scenario.id)
    assert_response :success
    assert_select "fieldset.board-choice", count: 0
  end

  test "piece-less map windows show as tabs, grouped by ToolbarMenu like VASSAL" do
    sign_in_as users(:one)
    charts = create_chart_maps_module!
    ModuleImportJob.perform_now(charts)
    game = create_game_for!(charts.reload)

    get game_path(game)
    assert_response :success

    # The ungrouped piece-less map is a plain tab; the grouped ones are not.
    ungrouped = charts.game_maps.find_by(name: "Alternative Display")
    assert_select "nav.map-tabs > a.map-tab[href=?]", game_path(game, map: ungrouped.id)
    crt = charts.game_maps.find_by(name: "Combat Results Table")
    tec = charts.game_maps.find_by(name: "Terrain Effects Chart")
    assert_select "nav.map-tabs > a.map-tab[href=?]", game_path(game, map: crt.id), count: 0

    # One dropdown with both chart maps; the no-match menu doesn't render.
    assert_select "details.map-menu", count: 1
    assert_select "details.map-menu summary", text: /Charts & Tables/
    assert_select "details.map-menu a.map-tab[href=?]", game_path(game, map: crt.id)
    assert_select "details.map-menu a.map-tab[href=?]", game_path(game, map: tec.id)
    assert_select "summary", text: /Unit Inventories/, count: 0

    # Opening a grouped chart map renders it and marks the menu active.
    get game_path(game, map: crt.id)
    assert_response :success
    assert_select "details.map-menu summary.active"
    assert_select "details.map-menu span.map-tab.active", text: /Combat Results Table/
  end

  private

  def create_game_for!(game_module)
    game = Game.create!(game_module: game_module, creator: users(:one), name: "Prueba",
                        scenario: game_module.scenarios.find_by(kind: "module_setup"))
    game.copy_scenario_pieces!
    game.players.create!(user: users(:one), side: "Bando A")
    game
  end

  def create_game!
    game = Game.create!(game_module: @game_module, scenario: @scenario,
                        creator: users(:one), name: "Prueba")
    game.copy_scenario_pieces!
    game.players.create!(user: users(:one), side: "Bando A")
    game
  end
end
