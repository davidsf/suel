require "zip"
require "nokogiri"

module Vassal
  # Reads a .vsav saved game: a ZIP with "savedata" (XML metadata) and
  # "savedGame" (obfuscated command stream).
  class SaveFile
    SAVED_GAME = "savedGame".freeze
    SAVE_DATA = "savedata".freeze

    Result = Struct.new(:description, :module_name, :commands, keyword_init: true)

    def self.parse(data)
      zip = Zip::File.open_buffer(StringIO.new(data.b))
      entry = zip.find_entry(SAVED_GAME) or raise ParseError, "no savedGame entry"
      stream = Obfuscation.deobfuscate(entry.get_input_stream.read)

      description = nil
      module_name = nil
      if (meta = zip.find_entry(SAVE_DATA))
        doc = Nokogiri::XML(meta.get_input_stream.read)
        description = doc.at_xpath("//data/description")&.text.presence
        module_name = doc.at_xpath("//data/moduleName")&.text.presence
      end

      commands = []
      Commands.each_leaf(stream) { |leaf| commands << leaf }
      Result.new(description:, module_name:, commands:)
    rescue Zip::Error => e
      raise ParseError, "vsav is not a zip: #{e.message}"
    end
  end
end
