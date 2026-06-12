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

  test "copy_scenario_pieces! copies placed pieces with baked stack offsets" do
    game = Game.create!(game_module: @game_module, scenario: @scenario,
                        creator: users(:one), name: "Prueba")
    game.copy_scenario_pieces!

    placed = @scenario.scenario_pieces.where.not(game_map_id: nil)
    assert_equal placed.count, game.game_pieces.count

    # Pieces sharing scenario coordinates must end up spread apart
    stacked = placed.group(:game_map_id, :x, :y).count.find { |_k, v| v > 1 }
    if stacked
      (map_id, x, y) = stacked.first
      copies = game.game_pieces.where(game_map_id: map_id)
        .where("x >= ? AND x < ?", x, x + 60).where("y > ? AND y <= ?", y - 60, y)
      assert_equal copies.count, copies.distinct.pluck(:x, :y).count,
        "stacked pieces should have distinct baked coordinates"
    end
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
