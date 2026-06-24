require "test_helper"

class Vassal::PredefinedSetupTest < ActiveSupport::TestCase
  test "flattens predefined setup menus into named setups with file and path" do
    xml = <<~XML
      <?xml version="1.0"?>
      <VASSAL.build.GameModule name="M" version="1" VassalVersion="3.7.0">
        <VASSAL.build.module.PredefinedSetup name="Setups" isMenu="true" useFile="true">
          <VASSAL.build.module.PredefinedSetup name="1517 Scenario" isMenu="false" useFile="true" file="1517_Scenario.vsav"/>
          <VASSAL.build.module.PredefinedSetup name="Campaign" isMenu="true" useFile="true">
            <VASSAL.build.module.PredefinedSetup name="Full Campaign" isMenu="false" useFile="true" file="campaign.vsav"/>
          </VASSAL.build.module.PredefinedSetup>
        </VASSAL.build.module.PredefinedSetup>
        <VASSAL.build.module.PredefinedSetup name="New game" isMenu="false" useFile="false"/>
      </VASSAL.build.GameModule>
    XML
    result = Vassal::BuildFile::GameModuleReader.read(Vassal::BuildFile.parse(xml))
    setups = result.predefined_setups

    by_name = setups.index_by(&:name)
    assert_equal "1517_Scenario.vsav", by_name["1517 Scenario"].file
    assert_equal [ "Setups" ], by_name["1517 Scenario"].menu_path
    assert_equal [ "Setups", "Campaign" ], by_name["Full Campaign"].menu_path
    assert by_name["New game"].empty
    assert_nil by_name["New game"].file

    assert_not_includes result.other_components.keys, "VASSAL.build.module.PredefinedSetup"
  end
end
