require "test_helper"

# A module-toolbar Global Key Command end to end, the Empire of the Sun way:
# the "Setup 1941" button fast-matches the control piece by BasicName and sends
# it SetupGame; its trigger fires SetupPieces, whose CounterGlobalKeyCommand
# broadcasts setup1941 to every on-map counter; each unit's SendToLocation
# places it on its scenario hex.
class GlobalKeySetupTest < ActiveSupport::TestCase
  include VmodTestHelper

  setup do
    @game_module = create_setup_module!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
    @scenario = @game_module.scenarios.find_by(kind: "module_setup")
    @game = Game.create!(game_module: @game_module, scenario: @scenario, creator: users(:one), name: "S")
    @map = @game_module.game_maps.find_by(name: "Main Map")
    @board = @map.boards.first
    @deck = @game_module.decks.find_by(name: "Hidden")
    @entry = @game.board_layout(@map).entries.first

    @control = @game.game_pieces.create!(game_map: @map, board: @board, x: @entry.x + 500, y: @entry.y + 350,
                                         z_order: 1, name: "Setup 1941 Scenario", type_string: "x",
                                         traits: setup_control_traits)
    @unit_a = @game.game_pieces.create!(game_map: @map, board: @board, x: @entry.x + 400, y: @entry.y + 300,
                                        z_order: 2, name: "Unit A", type_string: "x",
                                        traits: setup_unit_traits("0101", name: "Unit A"))
    @unit_b = @game.game_pieces.create!(game_map: @map, board: @board, x: @entry.x + 400, y: @entry.y + 300,
                                        z_order: 3, name: "Unit B", type_string: "x",
                                        traits: setup_unit_traits("0202", name: "Unit B"))
    # Wrong name: the button's BasicName fast-match must not send it SetupGame.
    # It would move if it received the keystroke.
    @bystander = @game.game_pieces.create!(game_map: @map, board: @board, x: @entry.x + 200, y: @entry.y + 200,
                                           z_order: 4, name: "Fake Setup", type_string: "x",
                                           traits: [
                                             { "kind" => "send_to", "key" => "named:SetupGame", "dest" => "G",
                                               "map" => "Main Map", "board" => "Board1", "grid_location" => "0202" },
                                             { "kind" => "basic", "image" => "board.png", "name" => "Fake Setup" }
                                           ])
    # A unit parked in a deck: COUNTER broadcasts don't reach decks.
    @decked = @game.game_pieces.create!(deck: @deck, deck_position: 0, name: "Decked", type_string: "x",
                                        traits: setup_unit_traits("0101", name: "Decked"))
  end

  teardown { FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s)) }

  test "the module button runs the whole setup chain" do
    gkc = @game_module.global_key_commands.first
    assert_equal "Setup 1941", gkc["text"]

    cmd = PieceCommand.broadcast(@game, gkc, by: "Bando A")

    [ @unit_a, @unit_b, @decked ].each(&:reload)
    assert_equal @board.point_for_location("0101").zip([ @entry.x, @entry.y ]).map(&:sum), [ @unit_a.x, @unit_a.y ]
    assert_equal @board.point_for_location("0202").zip([ @entry.x, @entry.y ]).map(&:sum), [ @unit_b.x, @unit_b.y ]
    assert @decked.in_deck?, "COUNTER broadcasts don't reach deck pieces"
    assert_equal [ @unit_a.id, @unit_b.id ].sort, cmd.touched.keys.sort
  end

  test "the BasicName fast-match excludes other pieces from the button keystroke" do
    bystander_before = [ @bystander.x, @bystander.y ]
    PieceCommand.broadcast(@game, @game_module.global_key_commands.first, by: "Bando A")
    assert_equal bystander_before, [ @bystander.reload.x, @bystander.reload.y ],
      "a piece with the wrong BasicName must not receive SetupGame"
  end

  test "a properties filter narrows a counter broadcast" do
    spec = { "kind" => "global_key", "global_key" => "named:setup1941",
             "target" => "COUNTER|false|MAP|||||0|0||false|||EQUALS||",
             "property_filter" => '{BasicName=="Unit A"}' }
    b_before = [ @unit_b.x, @unit_b.y ]

    PieceCommand.broadcast(@game, spec, by: "Bando A")

    assert_equal @board.point_for_location("0101").zip([ @entry.x, @entry.y ]).map(&:sum),
                 [ @unit_a.reload.x, @unit_a.reload.y ]
    assert_equal b_before, [ @unit_b.reload.x, @unit_b.reload.y ], "filtered out by BasicName"
  end
end
