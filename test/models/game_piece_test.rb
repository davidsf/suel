require "test_helper"

class GamePieceTest < ActiveSupport::TestCase
  include VmodTestHelper

  setup do
    @game_module = GameModule.new
    @game_module.package.attach(io: file_fixture("mini.vmod").open, filename: "mini.vmod", content_type: "application/zip")
    @game_module.save!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload

    @game = Game.create!(game_module: @game_module, scenario: @game_module.scenarios.vsav.first,
                         creator: users(:one), name: "Prueba")
    @game.copy_scenario_pieces!
    @piece = @game.game_pieces.first
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "move_to! updates position and brings the piece to the top" do
    top = @game.game_pieces.where(game_map_id: @piece.game_map_id).maximum(:z_order)
    @piece.move_to!(123, 456)
    @piece.reload
    assert_equal [ 123, 456 ], [ @piece.x, @piece.y ]
    assert_equal top + 1, @piece.z_order
  end

  test "rotate! steps the facing angle and persists" do
    piece = @game.game_pieces.detect { |p| p.traits.any? { |t| t["kind"] == "rotate" } }
    skip "fixture has no rotatable piece" unless piece

    trait = piece.traits.find { |t| t["kind"] == "rotate" }
    before = trait["angle"].to_f
    step = trait["free"] ? 15.0 : 360.0 / trait["facings"].to_i

    assert piece.rotate!(1)
    after = piece.reload.traits.find { |t| t["kind"] == "rotate" }["angle"].to_f
    assert_in_delta((before - step) % 360, after, 0.01)
  end

  test "cycle_layer! wraps through levels and persists" do
    piece = @game.game_pieces.detect { |p| p.traits.any? { |t| t["kind"] == "layer" && (t["images"] || []).size > 1 } }
    skip "fixture has no multi-level layer piece" unless piece

    trait = piece.traits.find { |t| t["kind"] == "layer" }
    size = trait["images"].size
    level = trait["value"].to_i.positive? ? trait["value"].to_i : 1

    assert piece.cycle_layer!(0, 1)
    after = piece.reload.traits.find { |t| t["kind"] == "layer" }["value"]
    assert_equal ((level - 1 + 1) % size) + 1, after
  end

  test "flip! toggles obscured_by when the piece has a mask" do
    piece = @game.game_pieces.detect { |p| p.traits.any? { |t| t["kind"] == "mask" } }
    if piece
      assert piece.flip!(by: "Bando A")
      assert_equal "Bando A", piece.reload.traits.find { |t| t["kind"] == "mask" }["obscured_by"]
      assert piece.flip!(by: "Bando A")
      assert_nil piece.reload.traits.find { |t| t["kind"] == "mask" }["obscured_by"]
    else
      assert_not @piece.flip!(by: "Bando A"), "flip without mask trait returns false"
    end
  end
end
