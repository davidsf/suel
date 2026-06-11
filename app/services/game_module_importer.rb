# Populates a GameModule's records from its extracted .vmod contents.
# Per-piece/per-scenario problems become parse_warnings, never failures.
class GameModuleImporter
  BATCH_SIZE = 500

  def initialize(game_module)
    @game_module = game_module
    @dir = game_module.extracted_dir
    @warnings = []
  end

  def import
    tree = Vassal::BuildFile.parse(read_build_file)
    result = Vassal::BuildFile::GameModuleReader.read(tree)
    @expander = Vassal::Piece::PrototypeExpander.new(result.prototypes)

    reset_children
    import_attributes(tree, result)
    import_prototypes(result)
    @maps_by_identifier = import_maps(result)
    import_palette(result)
    import_module_setup(result)
    import_save_files

    @warnings.concat(@expander.warnings)
    @game_module.update!(parse_warnings: @warnings.uniq, build_tree: tree.to_h)
  end

  private

  def warn(message)
    @warnings << message
  end

  def read_build_file
    name = Vassal::ModuleArchive::BUILD_FILE_NAMES.find { |n| File.file?(@dir.join(n)) } or
      raise Vassal::InvalidModuleError, "no buildFile in extracted module"
    File.read(@dir.join(name))
  end

  def reset_children
    @game_module.scenarios.destroy_all
    @game_module.piece_definitions.delete_all
    @game_module.game_maps.destroy_all
    @game_module.prototypes.delete_all
  end

  def import_attributes(tree, result)
    @game_module.update!(
      name: @game_module.name.presence || tree["name"],
      version: @game_module.version.presence || tree["version"],
      vassal_version: @game_module.vassal_version.presence || tree["VassalVersion"]
    )
    result.other_components.each do |class_name, count|
      warn "componente no soportado: #{class_name} (#{count})"
    end
  end

  def import_prototypes(result)
    rows = result.prototypes.map do |name, text|
      type, state = split_definition(text)
      { game_module_id: @game_module.id, name:, type_string: type, state_string: state,
        created_at: Time.current, updated_at: Time.current }
    end
    Prototype.insert_all(rows) if rows.any?
  end

  def split_definition(text)
    command = Vassal::Piece::AddCommand.parse(text)
    [ command.type, command.state ]
  rescue Vassal::ParseError
    [ text, "" ]
  end

  def import_maps(result)
    maps_by_identifier = {}
    result.maps.each_with_index do |map_info, index|
      identifier = map_info.name.presence || "Map#{index}"
      game_map = @game_module.game_maps.create!(
        name: map_info.name || identifier,
        kind: map_info.kind,
        side: map_info.side,
        position: index,
        settings: map_info.settings.merge("identifier" => identifier, "class" => map_info.class_name)
      )
      maps_by_identifier[identifier] = game_map

      map_info.boards.each_with_index do |board_info, board_index|
        game_map.boards.create!(
          name: board_info.name,
          image_filename: board_info.image,
          reversible: board_info.reversible,
          grid: board_info.grid,
          position: board_index,
          **board_dimensions(board_info.image)
        )
      end

      map_info.decks.each do |deck_info|
        deck = game_map.decks.create!(
          name: deck_info.name, owning_board: deck_info.owning_board,
          x: deck_info.x, y: deck_info.y, width: deck_info.width, height: deck_info.height,
          settings: deck_info.settings
        )
        insert_piece_definitions(deck_info.card_slots, deck:, path_prefix: [ game_map.name, deck_info.name ].compact)
      end
    end
    maps_by_identifier
  end

  def board_dimensions(image)
    return {} if image.blank?
    path = @dir.join("images", image)
    return {} unless File.file?(path)

    write_board_preview(path, image)
    width, height = Vassal::Images.dimensions(path)
    width ? { width:, height: } : {}
  end

  def write_board_preview(path, image)
    previews = @dir.join("previews")
    FileUtils.mkdir_p(previews)
    Vassal::Images.preview(path, previews.join("#{image}.jpg"))
  end

  def import_palette(result)
    insert_piece_definitions(result.piece_slots)
  end

  def insert_piece_definitions(slots, deck: nil, path_prefix: [])
    now = Time.current
    rows = slots.each_with_index.filter_map do |slot, index|
      parsed = parse_slot(slot) or next
      {
        game_module_id: @game_module.id,
        deck_id: deck&.id,
        gpid: slot.gpid,
        name: slot.name,
        slot_kind: slot.kind,
        palette_path: path_prefix + slot.path,
        type_string: parsed[:type],
        state_string: parsed[:state],
        traits: parsed[:traits],
        position: index,
        created_at: now, updated_at: now
      }
    end
    rows.each_slice(BATCH_SIZE) { |slice| PieceDefinition.insert_all(slice) }
  end

  def parse_slot(slot)
    command = Vassal::Piece::AddCommand.parse(slot.text)
    type, state = @expander.expand(command.type, command.state)
    { type:, state:, traits: Vassal::Piece.parse_traits(type, state) }
  rescue Vassal::ParseError => e
    warn "ficha ilegible #{slot.name.inspect} (gpid #{slot.gpid}): #{e.message}"
    nil
  end

  # Initial placements defined in the buildFile itself (SetupStack elements).
  def import_module_setup(result)
    stacks = result.maps.flat_map { |m| m.setup_stacks.map { |s| [ m, s ] } }
    return if stacks.empty?

    scenario = @game_module.scenarios.create!(
      name: "Despliegue del módulo", kind: "module_setup", status: "ready"
    )
    now = Time.current
    rows = stacks.flat_map do |map_info, stack|
      identifier = map_info.name.presence || "Map#{result.maps.index(map_info)}"
      game_map = @maps_by_identifier[identifier]
      stack.slots.each_with_index.filter_map do |slot, index|
        parsed = parse_slot(slot) or next
        {
          scenario_id: scenario.id,
          game_map_id: game_map&.id,
          board_id: resolve_board(game_map)&.id,
          map_identifier: identifier,
          x: stack.x, y: stack.y,
          gpid: slot.gpid, name: slot.name,
          z_order: index,
          type_string: parsed[:type],
          traits: parsed[:traits],
          state: { "location" => stack.location, "setup_stack" => stack.name }.compact,
          created_at: now, updated_at: now
        }
      end
    end
    rows.each_slice(BATCH_SIZE) { |slice| ScenarioPiece.insert_all(slice) }
  end

  def resolve_board(game_map)
    game_map && game_map.boards.one? ? game_map.boards.first : nil
  end

  def import_save_files
    Dir.glob(@dir.join("**", "*.vsav")).sort.each do |path|
      import_save_file(path)
    end
  end

  def import_save_file(path)
    relative = Pathname(path).relative_path_from(@dir).to_s
    scenario = @game_module.scenarios.create!(
      name: File.basename(path, ".vsav").tr("_", " "),
      kind: "vsav", source_filename: relative
    )
    save = Vassal::SaveFile.parse(File.read(path))
    scenario.update!(description: save.description)
    insert_scenario_pieces(scenario, save.commands)
    scenario.update!(status: "ready")
  rescue Vassal::Error, StandardError => e
    scenario&.update!(status: "failed", error_message: "#{e.class}: #{e.message}")
    warn "escenario ilegible #{relative}: #{e.message}"
  end

  def insert_scenario_pieces(scenario, commands)
    pieces = {}   # id => attrs hash
    stacks = []   # [{map:, x:, y:, member_ids: []}]
    z = 0

    commands.each do |leaf|
      command = Vassal::Commands.parse_leaf(leaf)
      case command
      when Vassal::Commands::AddPiece
        if command.type == "stack" || command.type.start_with?("deck;")
          stacks << parse_stack_state(command)
        else
          piece = build_scenario_piece(command, z)
          pieces[command.id || "anon-#{z}"] = piece if piece
        end
        z += 1
      when Vassal::Commands::MovePiece
        if (piece = pieces[command.id])
          piece[:map_identifier] = command.map_id
          piece[:x] = command.x
          piece[:y] = command.y
        end
      end
    end

    # Stack members carry no position of their own; spread them at the stack's
    # coordinates preserving the stack order for z.
    stacks.each do |stack|
      stack[:member_ids].each_with_index do |id, index|
        piece = pieces[id] or next
        piece[:map_identifier] = stack[:map]
        piece[:x] = stack[:x]
        piece[:y] = stack[:y]
        piece[:z_order] = piece[:z_order] + index
      end
    end

    now = Time.current
    rows = pieces.values.map do |piece|
      identifier = piece[:map_identifier]
      game_map = identifier && @maps_by_identifier[identifier]
      piece.merge(
        scenario_id: scenario.id,
        game_map_id: game_map&.id,
        board_id: resolve_board(game_map)&.id,
        created_at: now, updated_at: now
      )
    end
    rows.each_slice(BATCH_SIZE) { |slice| ScenarioPiece.insert_all(slice) }
  end

  def build_scenario_piece(command, z_order)
    type, state = @expander.expand(command.type, command.state)
    traits = Vassal::Piece.parse_traits(type, state)
    basic = traits.find { |t| t["kind"] == "basic" }
    return nil unless basic

    {
      piece_uid: command.id,
      map_identifier: basic["map"],
      x: basic["x"], y: basic["y"],
      gpid: basic["gpid"], name: basic["name"],
      z_order:,
      type_string: type,
      traits: traits,
      state: {}
    }
  rescue Vassal::ParseError
    warn "pieza ilegible en escenario (id #{command.id})"
    nil
  end

  # Stack state: "mapId;x;y;memberId;memberId;...;@@Layer" (Stack.java:606)
  def parse_stack_state(command)
    st = Vassal::SequenceEncoder::Decoder.new(command.state, ";")
    map_id = st.next_token("null")
    x = st.next_int(0)
    y = st.next_int(0)
    members = []
    while st.more_tokens?
      token = st.next_token
      members << token unless token.start_with?("@@")
    end
    { map: map_id == "null" ? nil : map_id, x:, y:, member_ids: members }
  end
end
