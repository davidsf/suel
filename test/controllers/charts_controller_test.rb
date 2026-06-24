require "test_helper"

class ChartsControllerTest < ActionDispatch::IntegrationTest
  include VmodTestHelper

  setup do
    @game_module = create_card_module!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "import populates the charts column from ChartWindow" do
    charts = @game_module.charts
    assert_equal 1, charts.size
    leaves = charts.first["charts"]
    assert_equal [ "CRT", "Terreno" ], leaves.map { |c| c["name"] }
    assert_equal [ "crt.gif", "terrain.gif" ], leaves.map { |c| c["image"] }
  end

  test "the charts page renders the chart images" do
    get game_module_charts_path(@game_module)
    assert_response :success
    assert_select ".charts-tabs button", text: "CRT"
    assert_match "crt.gif", response.body
  end

  test "the framed variant returns a turbo-frame for the in-game dialog" do
    get game_module_charts_path(@game_module, frame: 1)
    assert_response :success
    assert_select "turbo-frame#charts_frame"
  end
end
