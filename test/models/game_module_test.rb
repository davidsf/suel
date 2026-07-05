require "test_helper"

class GameModuleTest < ActiveSupport::TestCase
  # toolbar_menus derives VASSAL ToolbarMenu dropdowns from the persisted
  # build_tree at runtime (no import needed for these tests).
  def module_with(*menu_nodes)
    GameModule.new(build_tree: {
      "class" => "VASSAL.build.GameModule",
      "children" => menu_nodes
    })
  end

  def menu_node(attributes)
    { "class" => "VASSAL.build.module.ToolbarMenu", "attributes" => attributes }
  end

  test "toolbar_menus reads items and falls back to tooltip when text is empty" do
    game_module = module_with(menu_node(
      "text" => "", "tooltip" => "Charts & Tables", "description" => "Editor name",
      "icon" => "tables.png", "menuItems" => "CRT (Alt+C),TEC (Alt+T)"
    ))
    assert_equal [
      { "name" => "Charts & Tables", "icon" => "tables.png",
        "items" => [ "CRT (Alt+C)", "TEC (Alt+T)" ] }
    ], game_module.toolbar_menus
  end

  test "toolbar_menus decodes escaped commas as part of one item" do
    game_module = module_with(menu_node("text" => "Menu", "menuItems" => "One\\, Two,Three"))
    assert_equal [ "One, Two", "Three" ], game_module.toolbar_menus.first["items"]
  end

  test "toolbar_menus skips menus without items" do
    game_module = module_with(menu_node("text" => "Empty", "menuItems" => ""))
    assert_empty game_module.toolbar_menus
  end

  test "global_key_commands derives toolbar GKC buttons from the build_tree" do
    game_module = GameModule.new(build_tree: {
      "class" => "VASSAL.build.GameModule",
      "children" => [
        { "class" => "VASSAL.build.module.GlobalKeyCommand",
          "attributes" => { "name" => "1941 Campaign", "buttonText" => "Setup 1941",
                            "tooltip" => "Setup", "icon" => "setup.png",
                            "hotkey" => "57358,0,SetupGame", "deckCount" => "-1",
                            "filter" => "", "target" => "MODULE|false|MAP|X||||0|0||false|||EQUALS||" } },
        { "class" => "VASSAL.build.module.GlobalKeyCommand",
          "attributes" => { "name" => "Keyless", "buttonText" => "Keyless", "hotkey" => "" } },
        { "class" => "VASSAL.build.module.StartupGlobalKeyCommand",
          "attributes" => { "name" => "At startup", "hotkey" => "57359,0,Startup" } }
      ]
    })

    commands = game_module.global_key_commands
    assert_equal 1, commands.size, "keyless buttons and StartupGKCs are skipped"
    command = commands.first
    assert_equal "global_key", command["kind"]
    assert_equal "1941 Campaign", command["name"]
    assert_equal "Setup 1941", command["text"]
    assert_equal "named:SetupGame", command["global_key"]
    assert_nil command["count"], "-1 (all) maps to nil like the trait registry"
    assert_nil command["property_filter"]
  end

  test "toolbar_menus finds menus nested inside folders" do
    game_module = GameModule.new(build_tree: {
      "class" => "VASSAL.build.GameModule",
      "children" => [
        { "class" => "VASSAL.build.module.folder.GlobalPropertyFolder",
          "children" => [ menu_node("text" => "Nested", "menuItems" => "A,B") ] }
      ]
    })
    assert_equal [ "Nested" ], game_module.toolbar_menus.map { |m| m["name"] }
  end
end
