require "nokogiri"

module Vassal
  # Parses buildFile.xml (or the legacy extensionless buildFile) into a tree of
  # generic nodes. Element names are VASSAL Java class names; unknown ones are
  # kept verbatim so callers can degrade gracefully.
  class BuildFile
    Node = Struct.new(:class_name, :attributes, :text, :children, keyword_init: true) do
      # Last segment of the Java class name: "VASSAL.build.module.Map" -> "Map"
      def tag = class_name.split(".").last

      def [](attribute) = attributes[attribute]

      def children_tagged(tag_name) = children.select { |c| c.tag == tag_name }

      def descendants_tagged(tag_name)
        found = children_tagged(tag_name)
        children.each { |c| found.concat(c.descendants_tagged(tag_name)) }
        found
      end

      def to_h
        { "class" => class_name, "attributes" => attributes,
          "text" => text.presence, "children" => children.map(&:to_h) }.compact
      end
    end

    ROOT_CLASSES = %w[VASSAL.build.GameModule VASSAL.launch.BasicModule].freeze

    def self.parse(xml)
      doc = Nokogiri::XML(xml) { |config| config.options |= Nokogiri::XML::ParseOptions::HUGE }
      root = doc.root or raise ParseError, "buildFile has no root element"
      unless ROOT_CLASSES.include?(root.name)
        raise ParseError, "unexpected buildFile root: #{root.name}"
      end
      build_node(root)
    end

    def self.build_node(element)
      Node.new(
        class_name: element.name,
        attributes: element.attribute_nodes.to_h { |a| [ a.name, a.value ] },
        text: element.children.select { |c| c.text? || c.cdata? }.map(&:text).join.strip,
        children: element.element_children.map { |child| build_node(child) }
      )
    end
  end
end
