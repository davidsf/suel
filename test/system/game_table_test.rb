require "application_system_test_case"

class GameTableTest < ApplicationSystemTestCase
  include VmodTestHelper

  test "the table renders with contained chat and hidden piece toolbar" do
    game_module = GameModule.new
    game_module.package.attach(io: file_fixture("mini.vmod").open, filename: "mini.vmod", content_type: "application/zip")
    game_module.save!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    game = Game.create!(game_module:, scenario: game_module.scenarios.vsav.first,
                        creator: users(:one), name: "Mesa")
    game.copy_scenario_pieces!
    game.players.create!(user: users(:one), side: "Bando A")

    sign_in users(:one)

    visit game_path(game)
    assert_selector ".game-log"

    assert_no_selector ".piece-toolbar", visible: :visible,
      text: "Flip"
    input_width = page.evaluate_script('document.querySelector(".chat-form input[type=text]").offsetWidth')
    log_width = page.evaluate_script('document.querySelector(".game-log").offsetWidth')
    assert input_width < log_width, "chat input (#{input_width}px) must fit inside the log panel (#{log_width}px)"

    page.save_screenshot("/tmp/wv-table.png")
  end

  test "rolling a die reopens a collapsed log so the result is visible" do
    game_module = create_card_module! # ships a special die button
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    game = Game.create!(game_module:, scenario: game_module.scenarios.find_by(kind: "module_setup"),
                        creator: users(:one), name: "Mesa")
    game.copy_scenario_pieces!
    game.players.create!(user: users(:one), side: "Bando A")

    sign_in users(:one)
    visit game_path(game)

    # Collapse the log, then roll: the click should reopen it.
    page.execute_script("document.querySelector('details.game-log').open = false")
    assert_no_selector "details.game-log[open]"

    find(".dice-bar button", text: "Combate").click
    assert_selector "details.game-log[open]"
  end
end
