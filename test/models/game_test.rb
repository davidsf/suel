require "test_helper"

class GameTest < ActiveSupport::TestCase
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

  test "copy_scenario_pieces! copies placed pieces verbatim (stacks share coordinates)" do
    game = Game.create!(game_module: @game_module, scenario: @scenario,
                        creator: users(:one), name: "Prueba")
    game.copy_scenario_pieces!

    placed = @scenario.scenario_pieces.where.not(game_map_id: nil)
    assert_equal placed.count, game.game_pieces.count
    assert_equal placed.order(:z_order).pluck(:x, :y, :z_order).sort,
                 game.game_pieces.order(:z_order).pluck(:x, :y, :z_order).sort,
      "coordinates are copied as-is; the client fans stacks out"
  end

  test "board choice: game selection wins, scenario fallback, prompting only when unpinned" do
    game_module = create_multi_board_module!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    scenario = game_module.scenarios.find_by(kind: "module_setup")
    map = game_module.game_maps.kind_map.first

    assert_equal [ map ], scenario.maps_needing_board_choice

    game = Game.new(game_module:, scenario:, creator: users(:one), name: "Prueba")
    game.choose_boards({ map.identifier => "Small Map" })
    game.save!
    assert_equal "Small Map", game.board_layout(map).entries.first.board.name

    # No choice → first board (VASSAL's default selection).
    other = Game.new(game_module:, scenario:, creator: users(:one), name: "Prueba 2")
    other.choose_boards(nil)
    other.save!
    assert_equal "Full Map", other.board_layout(map).entries.first.board.name

    # A scenario that pins the map doesn't prompt, and the game defers to it.
    scenario.update!(board_setup: { map.identifier => [ { "name" => "Small Map", "col" => 0, "row" => 0, "reversed" => false } ] })
    assert_empty scenario.maps_needing_board_choice
    pinned = Game.create!(game_module:, scenario:, creator: users(:one), name: "Prueba 3")
    assert_equal "Small Map", pinned.board_layout(map).entries.first.board.name
  end

  test "an unknown chosen board fails validation" do
    game_module = create_multi_board_module!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    scenario = game_module.scenarios.find_by(kind: "module_setup")
    map = game_module.game_maps.kind_map.first

    game = Game.new(game_module:, scenario:, creator: users(:one), name: "Prueba")
    game.choose_boards({ map.identifier => "No Such Board" })
    assert_not game.valid?
    assert game.errors.of_kind?(:board_setup, :unknown_board)
  end

  test "sides falls back to generic sides when the module has no roster" do
    assert_equal [ "Bando A", "Bando B" ], @game_module.sides
  end

  test "free_sides excludes taken sides" do
    game = Game.create!(game_module: @game_module, scenario: @scenario,
                        creator: users(:one), name: "Prueba")
    game.players.create!(user: users(:one), side: "Bando A")
    assert_equal [ "Bando B" ], game.free_sides
  end

  test "player side must exist and be free" do
    game = Game.create!(game_module: @game_module, scenario: @scenario,
                        creator: users(:one), name: "Prueba")
    game.players.create!(user: users(:one), side: "Bando A")

    taken = game.players.build(user: users(:two), side: "Bando A")
    assert_not taken.valid?

    invented = game.players.build(user: users(:two), side: "Marciano")
    assert_not invented.valid?

    repeat = game.players.build(user: users(:one), side: "Bando B")
    assert_not repeat.valid?
  end
end
