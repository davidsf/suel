require "test_helper"

class Vassal::ModuleArchiveTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  test "reads a modern module with buildFile.xml" do
    path = make_zip("mod.vmod",
      "buildFile.xml" => "<VASSAL.build.GameModule/>",
      "moduledata" => "<data version='1'><name>Test</name></data>",
      "images/a.png" => "fake-png")

    Vassal::ModuleArchive.open(path) do |archive|
      assert_equal "buildFile.xml", archive.build_file_name
      assert_equal "<VASSAL.build.GameModule/>", archive.build_file_xml
      assert_includes archive.image_names, "images/a.png"
      assert_match "Test", archive.module_data_xml
    end
  end

  test "reads a legacy module with extensionless buildFile" do
    path = make_zip("legacy.vmod", "buildFile" => "<VASSAL.launch.BasicModule/>")

    Vassal::ModuleArchive.open(path) do |archive|
      assert_equal "buildFile", archive.build_file_name
    end
  end

  test "rejects a zip without buildFile" do
    path = make_zip("bad.vmod", "readme.txt" => "hi")

    Vassal::ModuleArchive.open(path) do |archive|
      assert_raises(Vassal::InvalidModuleError) { archive.build_file_name }
    end
  end

  test "rejects non-zip files" do
    path = File.join(@dir, "not-a-zip.vmod")
    File.write(path, "plain text")

    assert_raises(Vassal::InvalidModuleError) { Vassal::ModuleArchive.new(path) }
  end

  test "extract_all writes entries under the destination" do
    path = make_zip("mod.vmod",
      "buildFile.xml" => "<x/>",
      "images/deep/board.png" => "img")
    dest = File.join(@dir, "out")

    Vassal::ModuleArchive.open(path) { |a| a.extract_all(dest) }

    assert File.file?(File.join(dest, "buildFile.xml"))
    assert_equal "img", File.read(File.join(dest, "images/deep/board.png"))
  end

  test "extract_all refuses zip-slip paths" do
    path = File.join(@dir, "evil.vmod")
    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry("buildFile.xml")
      zip.write "<x/>"
      zip.put_next_entry("../evil.txt")
      zip.write "pwned"
    end
    dest = File.join(@dir, "out")

    Vassal::ModuleArchive.open(path) do |archive|
      assert_raises(Vassal::InvalidModuleError) { archive.extract_all(dest) }
    end
    assert_not File.exist?(File.join(@dir, "evil.txt"))
  end

  private

  def make_zip(name, entries)
    path = File.join(@dir, name)
    Zip::OutputStream.open(path) do |zip|
      entries.each do |entry_name, content|
        zip.put_next_entry(entry_name)
        zip.write content
      end
    end
    path
  end
end
