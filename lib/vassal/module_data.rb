require "nokogiri"

module Vassal
  # Parses the "moduledata" XML entry of a .vmod:
  #
  #   <data version="1">
  #     <name>...</name><version>...</version>
  #     <VassalVersion>...</VassalVersion><description>...</description>
  #   </data>
  class ModuleData
    Result = Struct.new(:name, :version, :vassal_version, :description, keyword_init: true)

    def self.parse(xml)
      doc = Nokogiri::XML(xml)
      Result.new(
        name: doc.at_xpath("//data/name")&.text.presence,
        version: doc.at_xpath("//data/version")&.text.presence,
        vassal_version: doc.at_xpath("//data/VassalVersion")&.text.presence,
        description: doc.at_xpath("//data/description")&.text.presence
      )
    end
  end
end
