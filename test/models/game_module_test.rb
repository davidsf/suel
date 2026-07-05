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
