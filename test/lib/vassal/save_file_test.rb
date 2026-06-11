require "test_helper"

class Vassal::SaveFileTest < ActiveSupport::TestCase
  test "parses a real legacy scenario from the fixture module" do
    vsav = Zip::File.open(file_fixture("mini.vmod")) do |zip|
      zip.entries.find { |e| e.name.end_with?(".vsav") }.get_input_stream.read
    end

    result = Vassal::SaveFile.parse(vsav)

    assert_includes result.commands, "begin_save"
    assert_includes result.commands, "end_save"

    adds = result.commands.filter_map { |c| Vassal::Commands.parse_leaf(c) }
      .grep(Vassal::Commands::AddPiece)
    assert adds.any?, "scenario should contain add-piece commands"

    placed = adds.reject { |a| a.type == "stack" || a.type.start_with?("deck;") }
    assert placed.any?
    placed.each do |add|
      traits = Vassal::Piece.parse_traits(add.type, add.state)
      assert traits.last.is_a?(Hash)
    end
  end

  test "rejects non-zip data" do
    assert_raises(Vassal::ParseError) { Vassal::SaveFile.parse("nope") }
  end
end
