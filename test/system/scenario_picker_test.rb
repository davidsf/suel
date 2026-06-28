require "application_system_test_case"

class ScenarioPickerTest < ApplicationSystemTestCase
  include VmodTestHelper

  setup do
    @game_module = create_card_module!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "picking a game opens its scenarios in a modal, closeable and re-openable" do
    sign_in users(:one)
    visit games_path

    # The dialog exists but stays closed until a game card is clicked.
    assert_no_selector ".scenario-dialog", visible: true
    assert_selector "a.card", text: "Cartas"

    click_on "Cartas"

    # Scenarios show centered in the modal, not appended below the grid.
    assert_selector ".scenario-dialog[open]", visible: true
    within ".scenario-dialog" do
      assert_text "Batalla del Río"
    end

    # The ✕ closes it.
    within ".scenario-dialog" do
      click_button "✕"
    end
    assert_no_selector ".scenario-dialog", visible: true

    # Re-clicking the same game re-opens the modal (turbo:frame-load fires again).
    click_on "Cartas"
    assert_selector ".scenario-dialog[open]", visible: true
  end
end
