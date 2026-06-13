require "application_system_test_case"

class ToolbarAnchorTest < ApplicationSystemTestCase
  include VmodTestHelper

  test "deck toolbar anchors near the deck and dismisses on background click" do
    game_module = create_card_module!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    scenario = game_module.scenarios.find_by(kind: "module_setup")
    game = Game.create!(game_module:, scenario:, creator: users(:one), name: "Cartas")
    game.copy_scenario_pieces!; game.materialize_decks!
    game.players.create!(user: users(:one), side: "Bando A")

    sign_in users(:one)
    visit game_path(game)
    assert_selector ".deck-marker.actionable", minimum: 1

    page.execute_script(<<~JS)
      const m = [...document.querySelectorAll(".deck-marker.actionable")].find(d => d.dataset.drawUrl)
      m.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }))
    JS
    assert_selector ".deck-toolbar", visible: true

    # Toolbar sits near the deck, not pinned to the screen bottom
    near = page.evaluate_script(<<~JS)
      (() => {
        const t = document.querySelector(".deck-toolbar").getBoundingClientRect()
        const m = [...document.querySelectorAll(".deck-marker.actionable")].find(d => d.dataset.drawUrl).getBoundingClientRect()
        return Math.abs(t.top - m.bottom) < 120
      })()
    JS
    assert near, "deck toolbar should be anchored just below the deck"

    # Clicking empty board background dismisses it
    page.execute_script(<<~JS)
      const v = document.querySelector(".viewer")
      const r = v.getBoundingClientRect()
      const opt = { bubbles: true, clientX: r.right - 20, clientY: r.bottom - 20 }
      v.dispatchEvent(new PointerEvent("pointerdown", opt))
      v.dispatchEvent(new PointerEvent("pointerup", opt))
    JS
    assert_no_selector ".deck-toolbar", visible: true
  end
end
