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

  def expected_snap(piece, x, y)
    entry = piece.layout_entry_at(x, y)
    return [ x, y ] unless entry
    lx, ly = entry.board.snap_point(x - entry.x, y - entry.y)
    [ lx + entry.x, ly + entry.y ]
  end

  test "move_to! updates position and brings the piece to the top" do
    top = @game.game_pieces.where(game_map_id: @piece.game_map_id).maximum(:z_order)
    expected = expected_snap(@piece, 123, 456)
    @piece.move_to!(123, 456)
    @piece.reload
    assert_equal expected, [ @piece.x, @piece.y ]
    assert_equal top + 1, @piece.z_order
  end

  test "move_to! snaps drops near a hex center back onto it" do
    board = @piece.layout_entry_at(500, 500)&.board
    skip "fixture piece has no snapping board with hex grid" unless board&.grid_type == "hex"

    @piece.move_to!(500, 500)
    cx, cy = @piece.reload.x, @piece.y
    @piece.move_to!(cx + 4, cy + 3)
    @piece.reload
    assert_equal [ cx, cy ], [ @piece.x, @piece.y ],
      "a drop near a hex center lands exactly on it (snap is a fixed point)"
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

  test "cycle_layer! wraps through the levels of an always-active layer" do
    piece = @game.game_pieces.create!(
      name: "phase", x: 0, y: 0, game_map: @piece.game_map,
      traits: [
        { "kind" => "layer", "name" => "Phase", "images" => [ "a.png", "b.png", "c.png" ],
          "value" => 1, "always_active" => true },
        { "kind" => "basic", "image" => "b.png", "name" => "phase" }
      ]
    )
    assert piece.cycle_layer!(0, 1)
    assert_equal 2, piece.reload.traits.first["value"]
    2.times { piece.cycle_layer!(0, 1) } # 2 -> 3 -> wrap to 1
    assert_equal 1, piece.reload.traits.first["value"], "wraps from the top back to level 1"
    assert piece.cycle_layer!(0, -1)
    assert_equal 3, piece.reload.traits.first["value"], "wraps below level 1 to the top"
  end

  test "blank+marker layers are on/off: a step shows the marker or hides it" do
    piece = @game.game_pieces.create!(
      name: "moved", x: 0, y: 0, game_map: @piece.game_map,
      traits: [
        { "kind" => "layer", "name" => "Moved", "images" => [ " ", "moved.png" ],
          "value" => 1, "always_active" => false },
        { "kind" => "basic", "image" => "b.png", "name" => "moved" }
      ]
    )
    # value 1 is the blank image (marker not shown) → a step turns the marker on
    assert piece.cycle_layer!(0, 1)
    assert_equal 2, piece.reload.traits.first["value"], "shows the marker image"
    assert piece.cycle_layer!(0, 1)
    assert_equal(-1, piece.reload.traits.first["value"], "hides the marker again")
  end

  test "single-image layers toggle activation on and off" do
    piece = @game.game_pieces.create!(
      name: "marker", x: 0, y: 0, game_map: @piece.game_map,
      traits: [
        { "kind" => "layer", "name" => "Column", "images" => [ "m.png" ], "value" => 1, "always_active" => false },
        { "kind" => "basic", "image" => "b.png", "name" => "marker" }
      ]
    )
    assert piece.cycle_layer!(0, 1)
    assert_equal(-1, piece.reload.traits.first["value"], "active marker toggles off")
    assert piece.cycle_layer!(0, 1)
    assert_equal 1, piece.reload.traits.first["value"], "inactive marker toggles on"
  end

  test "non-always-active multi-level layers deactivate below level 1 and clamp at top" do
    piece = @game.game_pieces.create!(
      name: "steps", x: 0, y: 0, game_map: @piece.game_map,
      traits: [
        { "kind" => "layer", "name" => "Steps", "images" => [ "a.png", "b.png", "c.png" ],
          "value" => 1, "always_active" => false },
        { "kind" => "basic", "image" => "b.png", "name" => "steps" }
      ]
    )
    assert piece.cycle_layer!(0, -1)
    assert_equal(-1, piece.reload.traits.first["value"], "below level 1 deactivates")
    assert piece.cycle_layer!(0, 1)
    assert_equal 1, piece.reload.traits.first["value"], "reactivates at level 1"
    2.times { piece.cycle_layer!(0, 1) }
    assert_equal 3, piece.reload.traits.first["value"]
    assert piece.cycle_layer!(0, 1)
    assert_equal 3, piece.reload.traits.first["value"], "clamps at the top level"
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
