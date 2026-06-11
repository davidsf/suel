require "test_helper"

class ViewersTest < ActionDispatch::IntegrationTest
  setup do
    @game_module = GameModule.new
    @game_module.package.attach(
      io: file_fixture("mini.vmod").open, filename: "mini.vmod", content_type: "application/zip"
    )
    @game_module.save!
    ModuleImportJob.perform_now(@game_module)
    @game_module.reload
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "module index and show render" do
    get root_path
    assert_response :success

    get game_module_path(@game_module)
    assert_response :success
    assert_match @game_module.name, response.body
  end

  test "board viewer renders with grid overlay" do
    board = @game_module.boards.first
    get game_module_board_path(@game_module, board)
    assert_response :success
    assert_match "pan-zoom", response.body
  end

  test "palette renders pieces" do
    get game_module_palette_path(@game_module)
    assert_response :success
    assert_match "piece-box", response.body
  end

  test "scenario viewer renders placed pieces" do
    scenario = @game_module.scenarios.vsav.first
    get game_module_scenario_path(@game_module, scenario)
    assert_response :success
  end
end
