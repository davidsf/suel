require "test_helper"

class ModuleImportJobTest < ActiveSupport::TestCase
  include VmodTestHelper

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "vassal-test", Process.pid.to_s))
  end

  test "imports a minimal module" do
    game_module = create_game_module!

    ModuleImportJob.perform_now(game_module)
    game_module.reload

    assert_equal "ready", game_module.status
    assert_equal "Mini Module", game_module.name
    assert_equal "1.0", game_module.version
    assert_equal "3.7.0", game_module.vassal_version
    assert File.file?(game_module.extracted_dir.join("images/board.png"))
  end

  test "imports the real legacy fixture module end to end" do
    game_module = GameModule.new
    game_module.package.attach(
      io: file_fixture("mini.vmod").open, filename: "mini.vmod", content_type: "application/zip"
    )
    game_module.save!

    ModuleImportJob.perform_now(game_module)
    game_module.reload

    assert_equal "ready", game_module.status
    assert game_module.game_maps.any?, "should create maps"
    assert game_module.boards.any?, "should create boards"
    assert game_module.prototypes.any?, "should create prototypes"
    assert game_module.piece_definitions.any?, "should create piece definitions"

    scenario = game_module.scenarios.vsav.first
    assert_equal "ready", scenario.status
    assert scenario.scenario_pieces.any?, "scenario should place pieces"
    assert scenario.scenario_pieces.where.not(x: nil).any?

    piece = game_module.piece_definitions.detect { |p| p.traits.any? { |t| t["kind"] == "basic" && t["image"].present? } }
    assert piece, "piece definitions should carry parsed traits with images"
  end

  test "marks the module failed on invalid archives" do
    game_module = GameModule.new
    game_module.package.attach(io: StringIO.new("not a zip"), filename: "bad.vmod", content_type: "application/zip")
    game_module.save!

    ModuleImportJob.perform_now(game_module)
    game_module.reload

    assert_equal "failed", game_module.status
    assert_match(/InvalidModuleError/, game_module.error_message)
  end
end
