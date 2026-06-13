require "application_system_test_case"

class PlayCardTest < ApplicationSystemTestCase
  include VmodTestHelper

  test "handCardDown drag plays the card via pointer events" do
    game_module = create_card_module!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    scenario = game_module.scenarios.find_by(kind: "module_setup")
    game = Game.create!(game_module:, scenario:, creator: users(:one), name: "Cartas")
    game.copy_scenario_pieces!; game.materialize_decks!
    game.players.create!(user: users(:one), side: "Bando A")
    card = game.game_pieces.where.not(deck_id: nil).first
    card.update!(deck_id: nil, deck_position: nil, hand_side: "Bando A")

    sign_in users(:one)
    visit game_path(game)
    # The tray starts collapsed; open it to reach the card.
    page.execute_script('document.querySelector(".hand-tray-open").click()')
    assert_selector "#hand_tray .hand-card", count: 1

    page.execute_script(<<~JS)
      const card = document.querySelector(".hand-card")
      const viewer = document.querySelector(".viewer")
      const r = viewer.getBoundingClientRect()
      const cx = r.left + r.width / 2, cy = r.top + r.height / 2
      const opts = (x, y) => ({ bubbles: true, pointerId: 1, clientX: x, clientY: y })
      card.dispatchEvent(new PointerEvent("pointerdown", opts(5, 5)))
      card.dispatchEvent(new PointerEvent("pointermove", opts(cx, cy)))
      card.dispatchEvent(new PointerEvent("pointerup", opts(cx, cy)))
    JS

    assert_selector "#hand_tray .hand-card", count: 0, wait: 5
    assert card.reload.on_map?
  end
end
