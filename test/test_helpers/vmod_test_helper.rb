module VmodTestHelper
  # Builds an in-memory minimal .vmod and returns it as an uploaded file blob.
  def build_vmod(entries)
    io = StringIO.new
    Zip::OutputStream.write_buffer(io) do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write content
      end
    end
    io.rewind
    io
  end

  def create_game_module!(entries = default_vmod_entries)
    game_module = GameModule.new
    game_module.package.attach(io: build_vmod(entries), filename: "mini.vmod", content_type: "application/zip")
    game_module.save!
    game_module
  end

  def default_vmod_entries
    {
      "buildFile.xml" => %(<?xml version="1.0"?><VASSAL.build.GameModule name="Mini" version="1.0" VassalVersion="3.7.0"/>),
      "moduledata" => %(<?xml version="1.0"?><data version="1"><name>Mini Module</name><version>1.0</version><VassalVersion>3.7.0</VassalVersion><description>Test module</description></data>),
      "images/board.png" => "fake-image-bytes"
    }
  end
end
