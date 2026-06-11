require "test_helper"

class ModuleAssetsControllerTest < ActionDispatch::IntegrationTest
  include VmodTestHelper

  setup do
    @game_module = create_game_module!
    ModuleImportJob.perform_now(@game_module)
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "serves extracted images with immutable caching" do
    get game_module_asset_path(@game_module.reload, path: "images/board.png")

    assert_response :success
    assert_equal "fake-image-bytes", response.body
    assert_match "immutable", response.headers["Cache-Control"]
  end

  test "rejects path traversal" do
    get "/game_modules/#{@game_module.reload.slug}/assets/..%2F..%2F..%2Fconfig%2Fdatabase.yml"

    assert_response :not_found
  end

  test "404 for missing files" do
    get game_module_asset_path(@game_module.reload, path: "images/nope.png")

    assert_response :not_found
  end
end
