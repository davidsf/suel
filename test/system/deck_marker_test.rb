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
    assert_selector ".hand-tray-open" # tray starts collapsed

    # Clicking a board deck (a cup) reveals the deck toolbar with its actions.
    # A cup is drawn VASSAL-style by dragging the top piece out, so it offers
    # Barajar/Rebarajar but not "Robar" (that draws to the hand, hand decks
    # only). The draw behaviour itself is covered by decks_controller_test;
    # here we only confirm the UI wiring.
    page.execute_script(<<~JS)
      const m = [...document.querySelectorAll(".deck-marker.actionable")].find(d => d.dataset.drawUrl)
      m.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }))
      m.dispatchEvent(new PointerEvent("pointerup", { bubbles: true }))
    JS
    assert_selector ".deck-toolbar", visible: true
    assert_button "Barajar"
    assert_no_button "Robar" # a cup is drawn by dragging, not "Robar" to hand
  end

  test "dragging a piece out of the cup drops it on the table" do
    game_module = create_card_module!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    scenario = game_module.scenarios.find_by(kind: "module_setup")
    game = Game.create!(game_module:, scenario:, creator: users(:one), name: "Cartas")
    game.copy_scenario_pieces!; game.materialize_decks!
    game.players.create!(user: users(:one), side: "Bando A")
    deck = game_module.decks.find_by(name: "Mazo")

    sign_in users(:one)
    visit game_path(game)
    assert_selector ".deck-marker.actionable", minimum: 1
    on_table = -> { page.all(".table-piece").count }
    before = on_table.call

    # Grab the top piece of the cup and drag it onto the board.
    page.execute_script(<<~JS)
      const m = document.querySelector('.deck-marker[data-draw-mode="board"]')
      const viewer = document.querySelector(".viewer")
      const r = viewer.getBoundingClientRect()
      const cx = r.left + r.width / 2, cy = r.top + r.height / 2
      const opts = (x, y) => ({ bubbles: true, pointerId: 1, button: 0, clientX: x, clientY: y })
      m.dispatchEvent(new PointerEvent("pointerdown", opts(5, 5)))
      m.dispatchEvent(new PointerEvent("pointermove", opts(cx, cy)))
      m.dispatchEvent(new PointerEvent("pointerup", opts(cx, cy)))
    JS

    assert_selector ".table-piece", count: before + 1, wait: 5
    assert_equal 2, game.game_pieces.in_deck(deck).count

    # Mazo is drawFaceUp: the drawn chit is revealed (its mask is cleared).
    drawn = game.game_pieces.on_map.detect { |p| %w[Diplomacia Asalto Refuerzo].include?(p.name) }
    assert drawn
    assert_nil drawn.traits.find { |t| t["kind"] == "mask" }["obscured_by"]
  end
end
