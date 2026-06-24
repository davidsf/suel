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
end
