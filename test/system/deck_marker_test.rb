require "application_system_test_case"

class DeckMarkerTest < ApplicationSystemTestCase
  include VmodTestHelper

  test "deck markers render and selecting one reveals the deck toolbar" do
    game_module = create_card_module!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    scenario = game_module.scenarios.find_by(kind: "module_setup")
    game = Game.create!(game_module:, scenario:, creator: users(:one), name: "Cartas")
    game.copy_scenario_pieces!
    game.materialize_decks!
    game.players.create!(user: users(:one), side: "Bando A")

    sign_in users(:one)

    visit game_path(game)
    assert_selector ".deck-marker.actionable", minimum: 1
    assert_selector ".hand-tray"

    # Selecting a deck reveals the deck toolbar with its actions. The
    # draw/shuffle/reshuffle behaviour itself is covered deterministically by
    # decks_controller_test; here we only confirm the UI wiring.
    page.execute_script(<<~JS)
      const m = [...document.querySelectorAll(".deck-marker.actionable")].find(d => d.dataset.drawUrl)
      m.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }))
    JS
    assert_selector ".deck-toolbar", visible: true
    assert_button "Robar"
  end
end
