module Vassal
  class BuildFile
    # Walks a BuildFile node tree and extracts the structures the app
    # understands: maps/boards/grids, decks with their cards, piece palettes,
    # prototypes, at-start stacks and player sides. Anything else is reported
    # in other_components instead of failing.
    class GameModuleReader
      MAP_CLASSES = {
        "VASSAL.build.module.Map" => "map",
        "VASSAL.build.module.PrivateMap" => "private",
        "VASSAL.build.module.PlayerHand" => "player_hand"
      }.freeze

      # Infrastructure components that need no web equivalent — not worth an
      # "unsupported" warning. Anything else unknown IS reported.
      IGNORED_CLASSES = %w[
        VASSAL.build.module.BasicCommandEncoder
        VASSAL.build.module.Documentation
        VASSAL.build.module.Chatter
        VASSAL.build.module.KeyNamer
        VASSAL.build.module.GlobalOptions
        VASSAL.i18n.Language
        VASSAL.build.module.properties.GlobalTranslatableMessages
        VASSAL.build.module.gamepieceimage.GamePieceImageDefinitions
        VASSAL.build.module.font.FontOrganizer
      ].freeze

      Result = Struct.new(:maps, :prototypes, :piece_slots, :sides, :other_components, keyword_init: true)
      MapInfo = Struct.new(:class_name, :name, :kind, :side, :settings, :boards, :decks, :setup_stacks, keyword_init: true)
      BoardInfo = Struct.new(:name, :image, :reversible, :grid, :width, :height, keyword_init: true)
      DeckInfo = Struct.new(:name, :owning_board, :x, :y, :width, :height, :settings, :card_slots, keyword_init: true)
      SetupStackInfo = Struct.new(:name, :owning_board, :x, :y, :location, :use_grid_location, :slots, keyword_init: true)
      SlotInfo = Struct.new(:name, :gpid, :width, :height, :text, :path, :kind, keyword_init: true)

      def self.read(root) = new(root).read

      def initialize(root)
        @root = root
      end

      def read
        @maps = []
        @prototypes = {}
        @piece_slots = []
        @sides = []
        @other = Hash.new(0)

        walk(@root.children)

        Result.new(maps: @maps, prototypes: @prototypes, piece_slots: @piece_slots,
                   sides: @sides, other_components: @other)
      end

      private

      # Folders (VASSAL 3.6+: VASSAL.build.module.folder.*) only organize the
      # editor tree; their children behave as if they were at the top level.
      def walk(nodes)
        nodes.each do |node|
          if node.class_name.include?(".folder.")
            walk(node.children)
          elsif (kind = map_kind(node))
            @maps << read_map(node, kind)
          elsif node.class_name == "VASSAL.build.module.PrototypesContainer"
            node.descendants_tagged("PrototypeDefinition").each do |proto|
              @prototypes[proto["name"]] = proto.text
            end
          elsif node.class_name == "VASSAL.build.module.PieceWindow"
            collect_slots(node, [], @piece_slots)
          elsif node.class_name == "VASSAL.build.module.PlayerRoster"
            @sides = node.children_tagged("entry").map(&:text)
          elsif !IGNORED_CLASSES.include?(node.class_name)
            @other[node.class_name] += 1
          end
        end
      end


      def map_kind(node)
        MAP_CLASSES[node.class_name] ||
          # Custom Map subclasses (e.g. tdc.TdcMap) still contain a BoardPicker
          ("map" if node.children.any? { |c| c.tag == "BoardPicker" })
      end

      def read_map(node, kind)
        MapInfo.new(
          class_name: node.class_name,
          name: node["mapName"].presence || node["name"].presence,
          kind: kind,
          side: node["side"].presence,
          settings: node.attributes,
          boards: node.children_tagged("BoardPicker").flat_map { |bp| bp.children_tagged("Board").map { |b| read_board(b) } },
          decks: node.descendants_tagged("DrawPile").map { |d| read_deck(d) },
          setup_stacks: node.descendants_tagged("SetupStack").map { |s| read_setup_stack(s) }
        )
      end

      def read_board(node)
        BoardInfo.new(
          name: node["name"],
          image: node["image"].presence,
          reversible: node["reversible"] == "true",
          grid: node.children.filter_map { |child| read_grid(child) }.first,
          # Imageless boards (player hands) size themselves via attributes
          width: node["width"]&.to_i,
          height: node["height"]&.to_i
        )
      end

      def read_grid(node)
        case node.tag
        when /HexGrid\z/, /SquareGrid\z/
          type = node.tag.end_with?("HexGrid") ? "hex" : "square"
          numbering = node.children.find { |c| c.tag.end_with?("Numbering") }
          {
            "type" => type,
            "dx" => node["dx"]&.to_f, "dy" => node["dy"]&.to_f,
            "x0" => node["x0"]&.to_i, "y0" => node["y0"]&.to_i,
            "sideways" => node["sideways"] == "true",
            "snap" => node["snapTo"] != "false",
            "edges" => node["edgesLegal"] == "true",
            "corners" => node["cornersLegal"] == "true",
            "visible" => node["visible"] == "true",
            "color" => node["color"].presence,
            "class" => (node.class_name unless node.class_name.start_with?("VASSAL.")),
            "numbering" => numbering&.attributes
          }.compact
        when "ZonedGrid"
          {
            "type" => "zoned",
            "background" => node.children.filter_map { |c| read_grid(c) unless c.tag == "Zone" }.first,
            "zones" => node.children_tagged("Zone").map { |z| read_zone(z) }
          }.compact
        when "RegionGrid"
          {
            "type" => "region",
            "regions" => node.descendants_tagged("Region").map do |r|
              { "name" => r["name"], "x" => r["originx"].to_i, "y" => r["originy"].to_i }
            end
          }
        when /Grid\z/
          { "type" => "unknown", "class" => node.class_name }
        end
      end

      def read_zone(node)
        path = node["path"].to_s.split(";").map { |point| point.split(",").map(&:to_i) }
        {
          "name" => node["name"],
          "path" => path,
          "use_parent_grid" => node["useParentGrid"] == "true",
          "location_format" => node["locationFormat"].presence,
          "grid" => node.children.filter_map { |c| read_grid(c) }.first
        }.compact
      end

      def read_deck(node)
        DeckInfo.new(
          name: node["name"],
          owning_board: node["owningBoard"].presence,
          x: node["x"].to_i, y: node["y"].to_i,
          width: node["width"].to_i, height: node["height"].to_i,
          settings: node.attributes,
          card_slots: node.children.filter_map { |child| read_slot(child, []) }
        )
      end

      def read_setup_stack(node)
        SetupStackInfo.new(
          name: node["name"],
          owning_board: node["owningBoard"].presence,
          x: node["x"].to_i, y: node["y"].to_i,
          location: node["location"].presence,
          use_grid_location: node["useGridLocation"] == "true",
          slots: node.children.filter_map { |child| read_slot(child, []) }
        )
      end

      # Depth-first walk of palette widgets (tabs, panels, lists...) keeping
      # the breadcrumb path of widget names down to each slot.
      def collect_slots(node, path, accumulator)
        node.children.each do |child|
          if (slot = read_slot(child, path))
            accumulator << slot
          else
            label = child["entryName"].presence || child["name"].presence
            collect_slots(child, label ? path + [ label ] : path, accumulator)
          end
        end
      end

      def read_slot(node, path)
        kind =
          case node.tag
          when "PieceSlot" then "piece"
          when "CardSlot" then "card"
          end
        return nil unless kind

        SlotInfo.new(
          name: node["entryName"],
          gpid: node["gpid"],
          width: node["width"]&.to_i,
          height: node["height"]&.to_i,
          text: node.text,
          path: path,
          kind: kind
        )
      end
    end
  end
end
