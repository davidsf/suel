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

      # Canonical form of a NamedKeyStroke token ("code,modifiers" or
      # "code,modifiers,name") for cross-piece matching: VASSAL matches named
      # keystrokes by name and physical ones by code+modifiers. Returns nil for
      # an empty token. The command bus compares these strings directly.
      def self.keystroke(token)
        token = token.to_s
        return nil if token.empty?
        code, modifiers, name = token.split(",", 3)
        name.to_s.empty? ? "key:#{code},#{modifiers}" : "named:#{name}"
      end

      # A StringArray of NamedKeyStroke tokens (',' delimited, inner commas
      # escaped) decoded to canonical keystrokes, empties dropped.
      def self.keystrokes(decoder)
        decoder.next_string_array.filter_map { |k| keystroke(k) }
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
        always_active = d.next_boolean(false)
        3.times { d.next_token("") } # activate/increase/decrease keystrokes
        d.next_token("") # description
        scale = d.next_double(1.0)

        # State is ";"-delimited (value;activationStatus...); only the leading
        # int matters here. Positive = active at that level, negative = inactive.
        value = SequenceEncoder::Decoder.new(state.to_s, ";").next_int(1)
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
        value = SequenceEncoder::Decoder.new(state.to_s, ";").next_int(1)
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

      # DynamicProperty "PROP;" — a per-piece named property (e.g. hit count).
      # Type: key ; "numeric,min,max,wrap" ; encoded change commands. State is
      # the current value. The change commands give the menu label (e.g. "Hit").
      def self.dynamic_property(type, state)
        d = decoder(type)
        name = d.next_token("")
        info = SequenceEncoder::Decoder.new(d.next_token(""), ",")
        numeric = info.next_token("false") == "true"
        min = info.next_int(0)
        max = info.next_int(0)
        wrap = info.next_token("false") == "true"
        label = command_label(d.next_token(""))
        { "kind" => "dynamic_property", "name" => name, "numeric" => numeric,
          "min" => min, "max" => max, "wrap" => wrap, "label" => label,
          "value" => state.to_s }.compact
      end

      # Menu name of the first change command, stripped of +/- and digits:
      # "+1 Hit:..." -> "Hit". Used to label the menu stepper.
      def self.command_label(commands)
        return nil if commands.blank?
        menu = SequenceEncoder::Decoder.new(commands, ",").next_token("").split(":").first.to_s
        menu.gsub(/[+\-\d]/, "").strip.presence
      end

      # TriggerAction "macro;" — a menu command (or watched keystrokes) that
      # performs a sequence of keystrokes on the piece. command is the
      # right-click menu text (blank = no menu item); key and watch_keys are the
      # triggers; action_keys are fired in order when triggered.
      def self.trigger_action(type, state)
        d = decoder(type)
        d.next_token("") # name
        command = d.next_token("")
        key = keystroke(d.next_token(""))
        property_match = d.next_token("")
        watch_keys = keystrokes(d)
        action_keys = keystrokes(d)
        { "kind" => "trigger", "command" => command.presence, "key" => key,
          "property_match" => property_match.presence,
          "watch_keys" => watch_keys, "action_keys" => action_keys }.compact
      end

      # SendToLocation "sendto;" — on a key command, moves the piece to a
      # destination. dest: L=fixed board point, G=by location name, Z=zone,
      # R=region. Names/locations support $property$ tokens, resolved at runtime.
      def self.send_to(type, state)
        d = decoder(type)
        command = d.next_token("")
        key = keystroke(d.next_token(""))
        map = d.next_token("")
        board = d.next_token("")
        x = d.next_token("")
        y = d.next_token("")
        6.times { d.next_token("") } # back command/key, x/y index, x/y offset
        d.next_token("") # description
        dest = d.next_token("L")
        zone = d.next_token("")
        region = d.next_token("")
        d.next_token("") # property filter
        grid_location = d.next_token("")
        { "kind" => "send_to", "command" => command.presence, "key" => key,
          "map" => map.presence, "board" => board.presence,
          "x" => (x.to_i if x.present?), "y" => (y.to_i if y.present?),
          "dest" => dest[0], "zone" => zone.presence, "region" => region.presence,
          "grid_location" => grid_location.presence }.compact
      end

      # CounterGlobalKeyCommand "globalkey;" — on a key command, sends global_key
      # to other pieces matching a target. We capture the deck name from the
      # GlobalCommandTarget descriptor (the pipe-delimited token), which is how
      # this game reveals a unit from a hidden-units deck.
      def self.global_key_command(type, state)
        d = decoder(type)
        command = d.next_token("")
        key = keystroke(d.next_token(""))
        global_key = keystroke(d.next_token(""))
        property_filter = d.next_token("")
        rest = []
        rest << d.next_token while d.more_tokens?
        target = rest.find { |t| t.to_s.include?("|") }
        # "Apply to N pieces of the deck" — the count sits right before the
        # target descriptor; absent/0 means apply to all matching pieces.
        count = target && rest[rest.index(target) - 1].to_s[/\A\d+\z/]&.to_i
        { "kind" => "global_key", "command" => command.presence, "key" => key,
          "global_key" => global_key, "property_filter" => property_filter.presence,
          "deck" => deck_from_target(target), "count" => count, "target" => target }.compact
      end

      # GlobalCommandTarget pipe-string: COUNTER|loc?|TYPE|map|board|zone|region|
      # x|y|deck|... — when TYPE is DECK the deck name follows 7 fields later.
      def self.deck_from_target(target)
        return nil if target.blank?
        parts = target.split("|", -1)
        idx = parts.index("DECK")
        idx && parts[idx + 7].presence
      end

      # SetGlobalProperty "setprop;" — extends DynamicProperty: each change
      # command maps a key to an operation on a named global property. op "P"
      # sets the value directly (a $property$-expandable expression), "I"
      # increments. Used here to record the marker's location before revealing.
      def self.set_global_property(type, state)
        d = decoder(type)
        name = d.next_token("")
        d.next_token("") # numeric,min,max,wrap constraints
        commands_raw = d.next_token("")
        d.next_token("") # description
        changes = SequenceEncoder::Decoder.new(commands_raw, ",").filter_map do |cmd|
          sub = SequenceEncoder::Decoder.new(cmd, ":")
          sub.next_token("") # menu name
          key = keystroke(sub.next_token(""))
          changer = SequenceEncoder::Decoder.new(sub.next_token(""), ",")
          op = changer.next_token("")
          next nil unless key && op.present?
          { "key" => key, "op" => op, "value" => changer.remaining }
        end
        { "kind" => "set_property", "name" => name.presence, "changes" => changes }.compact
      end

      # PlaceMarker "placemark;" — on a matching key, creates a new marker piece
      # at this piece's location. spec points to the marker's palette slot (a
      # "ClassName:Label" breadcrumb ending in the slot name); the trailing gpid
      # is the id stamped on the new instance, not the source slot's gpid.
      def self.place_marker(type, state)
        d = decoder(type)
        d.next_token("") # command (menu text; the firing TriggerAction carries it)
        key = keystroke(d.next_token(""))
        spec = d.next_token("")
        d.next_token("") # marker text
        x_off = d.next_int(0)
        y_off = d.next_int(0)
        match_rotation = d.next_boolean(false)
        d.next_token("") # afterburner key
        d.next_token("") # description
        gpid = d.next_token("")
        { "kind" => "place_marker", "key" => key, "spec" => spec.presence,
          "x_off" => x_off, "y_off" => y_off, "match_rotation" => match_rotation,
          "gpid" => gpid.presence }.compact
      end

      # ReportState "report;" — on a matching key, writes a message to the chat
      # log. keys are the triggering keystrokes; format is a $property$ template
      # ($location$, $newPieceName$ etc., resolved when reported).
      def self.report(type, state)
        d = decoder(type)
        keys = keystrokes(d)
        format = d.next_token("")
        { "kind" => "report", "keys" => keys, "format" => format.presence }.compact
      end

      # RestrictCommands "hideCmd;" — hides or disables other menu commands while
      # a property expression matches. action is "Hide" or "Disable"; keys are
      # the restricted commands' keystrokes.
      def self.restrict_commands(type, state)
        d = decoder(type)
        d.next_token("") # name
        action = d.next_token("")
        property_match = d.next_token("")
        keys = keystrokes(d)
        { "kind" => "restrict_commands", "action" => action.presence,
          "property_match" => property_match.presence, "keys" => keys }.compact
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
        "markmoved;" => method(:moved),
        "PROP;" => method(:dynamic_property),
        "macro;" => method(:trigger_action),
        "sendto;" => method(:send_to),
        "globalkey;" => method(:global_key_command),
        "setprop;" => method(:set_global_property),
        "placemark;" => method(:place_marker),
        "report;" => method(:report),
        "hideCmd;" => method(:restrict_commands)
      }.freeze
    end
  end
end
