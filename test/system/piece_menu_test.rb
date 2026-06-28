require "application_system_test_case"

class PieceMenuTest < ApplicationSystemTestCase
  include VmodTestHelper

  test "the piece action menu is a vertical list showing each layer's state" do
    game_module = GameModule.new
    game_module.package.attach(io: file_fixture("mini.vmod").open, filename: "mini.vmod", content_type: "application/zip")
    game_module.save!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    game = Game.create!(game_module:, scenario: game_module.scenarios.vsav.first,
                        creator: users(:one), name: "Mesa")
    game.copy_scenario_pieces!
    game.players.create!(user: users(:one), side: "Bando A")

    piece = game.game_pieces.on_map.first
    skip "fixture has no on-map piece" unless piece
    # An on/off layer (single image, inactive) and a multi-level layer (active
    # at level 2) — the two row styles the menu must render.
    piece.update!(traits: piece.traits + [
      { "kind" => "layer", "name" => "Activado", "images" => [ "m.png" ], "value" => -1, "always_active" => false },
      { "kind" => "layer", "name" => "Pasos", "images" => [ "a.png", "b.png", "c.png" ], "value" => 2, "always_active" => false }
    ])

    sign_in users(:one)
    visit game_path(game)
    el = "game_piece_#{piece.id}"
    assert_selector "##{el}", visible: :all

    # A real right-click fires pointerdown/up around the contextmenu event; the
    # menu must open and stay open (not be dismissed by the same gesture).
    page.execute_script(<<~JS)
      const p = document.getElementById("#{el}")
      p.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, button: 2, pointerId: 3 }))
      p.dispatchEvent(new MouseEvent("contextmenu", { bubbles: true }))
      p.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, button: 2, pointerId: 3 }))
    JS

    assert_selector ".piece-menu", visible: true
    within ".piece-menu" do
      # on/off layer → single clickable row showing ✓/—
      assert_selector "button.menu-row.clickable", text: "Activado", visible: :all
      # multi-level layer → stepper row showing the current level
      assert_selector ".menu-row", text: "Pasos", visible: :all
      assert_selector ".menu-stepper .menu-state", text: "2", visible: :all
    end

    # Background click dismisses it.
    page.execute_script(<<~JS)
      const v = document.querySelector(".viewer"), r = v.getBoundingClientRect()
      const o = { bubbles: true, clientX: r.right - 20, clientY: r.bottom - 20 }
      v.dispatchEvent(new PointerEvent("pointerdown", o))
      v.dispatchEvent(new PointerEvent("pointerup", o))
    JS
    assert_no_selector ".piece-menu", visible: true
  end

  test "the open menu reflects chosen options live, without reopening" do
    game_module = GameModule.new
    game_module.package.attach(io: file_fixture("mini.vmod").open, filename: "mini.vmod", content_type: "application/zip")
    game_module.save!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    game = Game.create!(game_module:, scenario: game_module.scenarios.vsav.first,
                        creator: users(:one), name: "Mesa")
    game.copy_scenario_pieces!
    game.players.create!(user: users(:one), side: "Bando A")
    piece = game.game_pieces.on_map.first
    skip "fixture has no on-map piece" unless piece
    # A single on/off marker, so the menu is short and the row is easy to click.
    basic = piece.traits.find { |t| t["kind"] == "basic" }
    piece.update!(traits: [ basic, { "kind" => "layer", "name" => "Moved",
      "images" => [ " ", "moved.png" ], "value" => 1, "always_active" => false } ].compact)

    sign_in users(:one)
    visit game_path(game)
    el = "game_piece_#{piece.id}"
    assert_selector "##{el}", visible: :all
    # Open the menu and toggle the marker via JS (the fixture piece can sit at
    # the board edge, so the floating menu may render off-screen — assert on the
    # DOM, not on viewport visibility).
    page.execute_script(%(document.getElementById("#{el}").dispatchEvent(new MouseEvent("contextmenu", { bubbles: true }))))

    assert_selector ".piece-menu .menu-row", text: "Moved", visible: :all
    assert_selector ".piece-menu .menu-state", text: "—", visible: :all   # marker off
    page.execute_script(<<~JS)
      [...document.querySelectorAll(".piece-menu button.menu-row.clickable")]
        .find(b => b.textContent.includes("Moved")).click()
    JS
    # The open menu rebuilds from the piece's new state without reopening.
    assert_selector ".piece-menu .menu-state", text: "✓", visible: :all
  end

  test "a single tap only selects; a double tap opens the menu" do
    game_module = GameModule.new
    game_module.package.attach(io: file_fixture("mini.vmod").open, filename: "mini.vmod", content_type: "application/zip")
    game_module.save!
    ModuleImportJob.perform_now(game_module)
    game_module.reload
    game = Game.create!(game_module:, scenario: game_module.scenarios.vsav.first,
                        creator: users(:one), name: "Mesa")
    game.copy_scenario_pieces!
    game.players.create!(user: users(:one), side: "Bando A")
    piece = game.game_pieces.on_map.first
    skip "fixture has no on-map piece" unless piece

    sign_in users(:one)
    visit game_path(game)
    el = "game_piece_#{piece.id}"
    assert_selector "##{el}", visible: :all

    tap = <<~JS
      const p = document.getElementById("#{el}")
      p.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerId: 1 }))
      p.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, pointerId: 1 }))
    JS

    # One tap selects the piece but leaves the menu closed.
    page.execute_script(tap)
    assert_selector "##{el}.selected", visible: :all
    assert_no_selector ".piece-menu", visible: true

    # A second tap on the same piece opens the menu.
    page.execute_script(tap)
    assert_selector ".piece-menu", visible: true
  end
end
