require "application_system_test_case"

class HandTrayToggleTest < ApplicationSystemTestCase
  include VmodTestHelper

  test "the hand tray can be closed and reopened" do
    game_module = create_card_module!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    scenario = game_module.scenarios.find_by(kind: "module_setup")
    game = Game.create!(game_module:, scenario:, creator: users(:one), name: "Cartas")
    game.copy_scenario_pieces!; game.materialize_decks!
    game.players.create!(user: users(:one), side: "Bando A")

    sign_in users(:one)
    visit game_path(game)

    # The tray starts collapsed; opening shows it, closing hides it again.
    # Fixed elements at the viewport edge are flaky for Selenium's native
    # click, so trigger the wiring directly; the feature itself is plain CSS.
    assert_no_selector ".hand-tray", visible: true
    assert_selector ".hand-tray-open", visible: true

    page.execute_script('document.querySelector(".hand-tray-open").click()')
    assert_selector ".hand-tray", visible: true
    assert_no_selector ".hand-tray-open", visible: true

    page.execute_script('document.querySelector(".hand-tray-close").click()')
    assert_no_selector ".hand-tray", visible: true
    assert_selector ".hand-tray-open", visible: true
  end
end
