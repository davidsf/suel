require "test_helper"

class Vassal::ObfuscationTest < ActiveSupport::TestCase
  test "plain text passes through" do
    assert_equal "begin_save", Vassal::Obfuscation.deobfuscate("begin_save")
  end

  test "round trip" do
    original = "begin_save\e+/null/piece;;;x.png;Name/null;0;0;1;0\eend_save"
    obfuscated = Vassal::Obfuscation.obfuscate(original)
    assert obfuscated.start_with?("!VCSK")
    assert_equal original, Vassal::Obfuscation.deobfuscate(obfuscated)
  end

  test "deobfuscates a real savedGame from the fixture module" do
    vsav = read_fixture_vsav
    Zip::File.open_buffer(StringIO.new(vsav)) do |zip|
      data = zip.find_entry("savedGame").get_input_stream.read
      plain = Vassal::Obfuscation.deobfuscate(data)
      assert_includes plain, "begin_save"
    end
  end

  private

  def read_fixture_vsav
    Zip::File.open(file_fixture("mini.vmod")) do |zip|
      entry = zip.entries.find { |e| e.name.end_with?(".vsav") }
      return entry.get_input_stream.read
    end
  end
end
