require "test_helper"

class ScenarioNamingTest < ActiveSupport::TestCase
  include VmodTestHelper

  setup do
    @game_module = create_card_module!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "a .vsav named by a PredefinedSetup uses the setup name and menu category" do
    scenario = @game_module.scenarios.find_by(source_filename: "batalla.vsav")
    assert_not_nil scenario
    assert_equal "Batalla del Río", scenario.name
    assert_equal "Escenarios", scenario.category
    assert_equal "ready", scenario.status
  end

  test "with PredefinedSetups, only the referenced .vsav files are imported" do
    entries = card_vmod_entries.merge("suelto.vsav" => card_vsav)
    game_module = create_game_module!(entries)
    ModuleImportJob.perform_now(game_module)

    files = game_module.scenarios.vsav.pluck(:source_filename)
    assert_includes files, "batalla.vsav"
    assert_not_includes files, "suelto.vsav"
  end

  test "without any PredefinedSetup, every loose .vsav is imported" do
    entries = default_vmod_entries.merge("uno.vsav" => card_vsav, "dos.vsav" => card_vsav)
    game_module = create_game_module!(entries)
    ModuleImportJob.perform_now(game_module)

    files = game_module.scenarios.vsav.pluck(:source_filename)
    assert_equal %w[dos.vsav uno.vsav], files.sort
  end
end
