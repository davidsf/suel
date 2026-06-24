require "test_helper"

class Vassal::BuildFileTest < ActiveSupport::TestCase
  test "parses the legacy fixture buildFile into maps, slots and prototypes" do
    xml = Zip::File.open(file_fixture("mini.vmod")) do |zip|
      zip.find_entry("buildFile").get_input_stream.read
    end

    tree = Vassal::BuildFile.parse(xml)
    assert_equal "VASSAL.launch.BasicModule", tree.class_name

    result = Vassal::BuildFile::GameModuleReader.read(tree)
    assert result.maps.any?, "should find at least one map"
    assert result.piece_slots.any?, "should find palette piece slots"
    assert result.prototypes.any?, "should find prototype definitions"

    map = result.maps.first
    assert map.boards.any?
    assert result.piece_slots.first.path.any?, "slots carry their palette breadcrumb"
  end

  test "rejects non-vassal xml" do
    assert_raises(Vassal::ParseError) { Vassal::BuildFile.parse("<html/>") }
  end

  test "infrastructure components are not reported as unsupported" do
    xml = <<~XML
      <?xml version="1.0"?>
      <VASSAL.build.GameModule name="M" version="1" VassalVersion="3.7.0">
        <VASSAL.build.module.properties.GlobalProperties/>
        <VASSAL.build.module.GlobalKeyCommand/>
        <VASSAL.build.module.StartupGlobalKeyCommand/>
        <VASSAL.build.module.ToolbarMenu/>
        <VASSAL.build.module.DiceButton name="d6" nDice="1" nSides="6"/>
        <tdc.TdcCommandEncoder/>
      </VASSAL.build.GameModule>
    XML
    result = Vassal::BuildFile::GameModuleReader.read(Vassal::BuildFile.parse(xml))

    unsupported = result.other_components.keys
    assert_not_includes unsupported, "VASSAL.build.module.properties.GlobalProperties"
    assert_not_includes unsupported, "VASSAL.build.module.GlobalKeyCommand"
    assert_not_includes unsupported, "VASSAL.build.module.StartupGlobalKeyCommand"
    assert_not_includes unsupported, "VASSAL.build.module.ToolbarMenu"
    assert_not_includes unsupported, "VASSAL.build.module.DiceButton"
    # genuinely unsupported (custom Java) is still surfaced
    assert_includes unsupported, "tdc.TdcCommandEncoder"
  end
end
