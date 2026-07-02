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

  test "palette, charts and scenario picker render" do
    get game_module_palette_path(@game_module)
    assert_response :success

    get game_module_charts_path(@game_module)
    assert_response :success

    get game_module_scenarios_path(@game_module)
    assert_response :success
  end

  test "the UI follows the browser's Accept-Language" do
    get root_path
    assert_match "Modules", response.body, "defaults to English"

    get root_path, headers: { "Accept-Language" => "es-ES,es;q=0.9,en;q=0.8" }
    assert_match "Módulos", response.body

    get root_path, headers: { "Accept-Language" => "fr-FR,fr;q=0.9" }
    assert_match "Modules", response.body, "unsupported languages fall back to English"
  end

  test "a signed-in admin sees the upload link on public pages" do
    sign_in_as users(:admin)
    get root_path
    assert_match "Upload module", response.body

    get game_module_path(@game_module)
    assert_match "Reimport", response.body
  end

  test "anonymous visitors see no admin actions" do
    get root_path
    assert_no_match "Upload module", response.body
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
