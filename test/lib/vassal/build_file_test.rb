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
end
