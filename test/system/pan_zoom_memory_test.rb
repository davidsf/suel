require "application_system_test_case"

class PanZoomMemoryTest < ApplicationSystemTestCase
  include VmodTestHelper

  test "the map view survives navigating away and back" do
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
    assert_selector ".world"
    zoom_in = %q{document.querySelector('[data-action="pan-zoom#zoomIn"]').click()}
    page.execute_script(zoom_in)
    page.execute_script(zoom_in)
    zoomed = page.evaluate_script('document.querySelector(".world").style.transform')
    assert_match(/scale/, zoomed)

    visit game_path(game)
    assert_selector ".world"
    restored = -> { page.evaluate_script('document.querySelector(".world").style.transform') }
    # The transform is applied by JS on connect; give Stimulus a beat.
    assert page.document.synchronize { restored.call == zoomed || raise(Capybara::ElementNotFound) },
      "expected the restored view #{restored.call.inspect} to equal #{zoomed.inspect}"
  end
end
