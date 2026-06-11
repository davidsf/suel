module Vassal
  module Piece
    # Decodes individual trait TYPE/STATE strings into plain hashes (string
    # keys, JSON-ready). Field orders are ports of each trait's mySetType /
    # myGetState in VASSAL/counters/*.java. Unknown or unparseable traits come
    # back as kind "unknown" — graceful degradation is the contract here.
    module TraitRegistry
      def self.parse(type, state)
        prefix = type[/\A[^;]*;?/]
        parser = PARSERS[prefix]
        result = parser ? parser.call(type, state.to_s) : nil
        result || unknown(type, state)
      rescue StandardError
        unknown(type, state)
      end

      def self.unknown(type, state)
        { "kind" => "unknown", "id" => type[/\A[^;]*/], "raw" => type, "raw_state" => state.to_s }
      end

      def self.decoder(string, skip_id: true)
        d = SequenceEncoder::Decoder.new(string, ";")
        d.next_token if skip_id
        d
      end

      def self.basic(type, state)
        d = decoder(type)
        st = SequenceEncoder::Decoder.new(state, ";")
        map = st.next_token("null")
        result = {
          "kind" => "basic",
          "clone_key" => d.next_token(""),
          "delete_key" => d.next_token(""),
          "image" => d.next_token(""),
          "name" => d.next_token(""),
          "map" => map == "null" ? nil : map,
          "x" => st.next_int(0),
          "y" => st.next_int(0),
          "gpid" => st.next_token("")
        }
        properties = {}
        st.next_int(0).times do
          key = st.next_token("")
          properties[key] = st.next_token("")
        end
        result["properties"] = properties unless properties.empty?
        result
      end

      # Embellishment "emb2;" (Embellishment.java mySetType). The state is the
      # current value: positive = active at level value, negative = inactive.
      def self.layer(type, state)
        d = decoder(type)
        12.times { d.next_token("") } # activate/up/down/reset commands, modifiers and keys
        d.next_boolean(false)         # drawUnderneathWhenSelected
        x_off = d.next_int(0)
        y_off = d.next_int(0)
        images = d.next_string_array(1)
        names = d.next_string_array(images.length)
        d.next_boolean(true) # loopLevels
        name = d.next_token("")
        2.times { d.next_token("") } # random layer key/text
        follow_property = d.next_boolean(false)
        property_name = d.next_token("")
        first_level = d.next_int(1)
        d.next_int(0) # version
        always_active = d.next_boolean(true)
        3.times { d.next_token("") } # activate/increase/decrease keystrokes
        d.next_token("") # description
        scale = d.next_double(1.0)

        value = Integer(state, exception: false) || 1
        {
          "kind" => "layer", "name" => name,
          "images" => images, "level_names" => names,
          "x_off" => x_off, "y_off" => y_off, "scale" => scale,
          "always_active" => always_active,
          "follow_property" => follow_property.presence && property_name,
          "first_level" => first_level,
          "value" => value
        }.compact
      end

      # Legacy "emb;" (Embellishment.java originalSetType): images come as
      # trailing "image,name" tokens.
      def self.legacy_layer(type, state)
        d = decoder(type)
        d.next_token("") # activation spec (sub-encoded)
        d.next_token("") # activateCommand
        4.times { d.next_token("") } # up/down keys and commands
        x_off = d.next_int(0)
        y_off = d.next_int(0)
        images = []
        names = []
        while d.more_tokens?
          sub = SequenceEncoder::Decoder.new(d.next_token, ",")
          images << sub.next_token("")
          names << sub.next_token("")
        end
        value = Integer(state, exception: false) || 1
        {
          "kind" => "layer",
          "images" => images, "level_names" => names,
          "x_off" => x_off, "y_off" => y_off,
          "always_active" => false, "first_level" => 1,
          "value" => value
        }
      end

      # Labeler "label;" — state is the label text itself.
      def self.label(type, state)
        d = decoder(type)
        d.next_token("") # labelKey
        d.next_token("") # menuCommand
        font_size = d.next_int(10)
        bg = d.next_token("")
        fg = d.next_token("")
        vertical_pos = d.next_token("t")
        d.next_int(0)
        horizontal_pos = d.next_token("c")
        d.next_int(0)
        2.times { d.next_token("") } # justification
        name_format = d.next_token("")
        d.next_token("") # font family
        d.next_int(0)    # font style
        rotate = d.next_int(0)
        {
          "kind" => "label", "text" => state,
          "format" => name_format, "font_size" => font_size,
          "fg" => fg.presence, "bg" => bg.presence,
          "vertical_pos" => vertical_pos, "horizontal_pos" => horizontal_pos,
          "rotate" => rotate
        }.compact
      end

      # Marker "mark;" — type lists keys (comma sequence), state lists values.
      def self.marker(type, state)
        keys = SequenceEncoder::Decoder.new(type.delete_prefix("mark;"), ",").to_a
        values = SequenceEncoder::Decoder.new(state, ",").to_a
        { "kind" => "marker", "properties" => keys.zip(values).to_h { |k, v| [ k, v || "" ] } }
      end

      # Obscurable "obs;" — mask/flip support. displayStyle first char:
      # I=inset, P=peek, G=image (rest of token is the image shown to others).
      def self.mask(type, state)
        d = decoder(type)
        d.next_token("") # keyCommand
        back_image = d.next_token("")
        d.next_token("") # hideCommand
        style = d.next_token("I")
        others_image = style[0] == "G" ? style[1..] : nil
        mask_name = d.next_token("?")
        access = d.next_token("")
        st = SequenceEncoder::Decoder.new(state, ";")
        obscured_by = st.next_token("null")
        {
          "kind" => "mask",
          "back_image" => back_image.presence,
          "others_image" => others_image.presence,
          "display_style" => style[0],
          "mask_name" => mask_name,
          "access" => access.presence,
          "obscured_by" => obscured_by == "null" ? nil : obscured_by
        }.compact
      end

      # FreeRotator "rotate;" — 1 valid angle means free rotation (state is the
      # angle in degrees); otherwise state is the facing index.
      def self.rotate(type, state)
        d = decoder(type)
        facings = d.next_int(1)
        free = facings == 1
        angle =
          if free
            Float(state, exception: false) || 0.0
          else
            index = Integer(state, exception: false) || 0
            -index * (360.0 / facings)
          end
        { "kind" => "rotate", "facings" => facings, "free" => free, "angle" => angle }
      end

      def self.invisible(type, state)
        { "kind" => "invisible", "hidden_by" => state == "null" ? nil : state.presence }
      end

      def self.prototype(type, state)
        d = decoder(type)
        { "kind" => "prototype", "name" => d.next_token("") }
      end

      def self.moved(type, state)
        { "kind" => "moved" }
      end

      PARSERS = {
        "piece;" => method(:basic),
        "emb2;" => method(:layer),
        "emb;" => method(:legacy_layer),
        "label;" => method(:label),
        "mark;" => method(:marker),
        "obs;" => method(:mask),
        "rotate;" => method(:rotate),
        "hide;" => method(:invisible),
        "prototype;" => method(:prototype),
        "markmoved;" => method(:moved)
      }.freeze
    end
  end
end
