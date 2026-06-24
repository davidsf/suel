require "test_helper"
require "turbo/broadcastable/test_helper"

class RollsControllerTest < ActionDispatch::IntegrationTest
  include VmodTestHelper
  include Turbo::Broadcastable::TestHelper

  DICE_TREE = {
    "class" => "VASSAL.build.GameModule",
    "children" => [
      { "class" => "VASSAL.build.module.folder.ModuleSubFolder", "children" => [
        { "class" => "VASSAL.build.module.DiceButton",
          "attributes" => { "name" => "2d6", "text" => "2d6", "nDice" => "2", "nSides" => "6", "plus" => "0", "reportTotal" => "false" } }
      ] }
    ]
  }.freeze

  setup do
    @game_module = create_game_module!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload.update!(build_tree: DICE_TREE)

    scenario = @game_module.scenarios.create!(name: "Setup", kind: "module_setup", status: "ready")
    @game = Game.create!(game_module: @game_module, scenario: scenario,
                         creator: users(:one), name: "Prueba")
    @game.players.create!(user: users(:one), side: "Bando A")
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "dice buttons are read from the build tree, folders included" do
    buttons = @game_module.dice_buttons
    assert_equal 1, buttons.size
    assert_equal [ "2d6", 2, 6 ], buttons.first.values_at("name", "n_dice", "n_sides")
  end

  test "a player rolls and the result is logged and broadcast" do
    sign_in_as users(:one)

    assert_turbo_stream_broadcasts(@game, count: 1) do
      assert_difference "GameEvent.count", 1 do
        post game_rolls_path(@game, button: 0)
      end
    end
    assert_response :success

    event = GameEvent.last
    assert_match(/2d6/, event.body)
    assert_match(/Bando A/, event.body)
    dice = event.payload["dice"]
    assert_equal 2, dice.size
    assert dice.all? { |d| (1..6).cover?(d) }
  end

  test "spectators cannot roll" do
    sign_in_as users(:two)
    post game_rolls_path(@game, button: 0)
    assert_response :forbidden
  end

  test "unknown button is rejected" do
    sign_in_as users(:one)
    post game_rolls_path(@game, button: 7)
    assert_response :unprocessable_entity
  end

  test "a special (image) die rolls a valid face and logs it" do
    # Build a module with a SpecialDiceButton
    special = create_card_module!
    ModuleImportJob.perform_now(special)
    special.reload
    scenario = special.scenarios.find_by(kind: "module_setup")
    game = Game.create!(game_module: special, scenario:, creator: users(:one), name: "Esp")
    game.players.create!(user: users(:one), side: "Bando A")

    assert_equal 1, special.special_dice.size
    sign_in_as users(:one)
    assert_difference "GameEvent.count", 1 do
      post game_rolls_path(game, special: 0)
    end
    assert_response :success

    event = GameEvent.last
    assert_match(/Dado de combate/, event.body)
    face = event.payload["faces"].first
    assert_includes [ "Fallo", "Impacto" ], face["text"]
    assert_includes [ "die-1.png", "die-2.png" ], face["icon"]
  end

  test "spectators cannot roll special dice" do
    special = create_card_module!
    ModuleImportJob.perform_now(special)
    game = Game.create!(game_module: special.reload, scenario: special.scenarios.find_by(kind: "module_setup"),
                        creator: users(:one), name: "Esp")
    game.players.create!(user: users(:one), side: "Bando A")
    sign_in_as users(:two)
    post game_rolls_path(game, special: 0)
    assert_response :forbidden
  end
end
