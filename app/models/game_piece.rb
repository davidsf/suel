class GamePiece < ApplicationRecord
  belongs_to :game
  belongs_to :game_map, optional: true
  belongs_to :board, optional: true
  belongs_to :deck, optional: true

  # A piece is in exactly one place: in a deck, in a player's hand, or on a map.
  validate :one_location_at_most

  # Instantiates a palette definition as a new piece on a map, on top of the
  # stack at the given point — used by PlaceMarker to stamp a marker counter.
  # The point is already in map space (snapped to the source piece).
  def self.create_on_map!(game:, game_map:, board:, x:, y:, definition:, gpid: nil)
    top = game.game_pieces.where(game_map_id: game_map.id).maximum(:z_order).to_i
    create!(game: game, game_map: game_map, board: board, x: x, y: y, z_order: top + 1,
            name: definition.name, type_string: definition.type_string,
            gpid: gpid || definition.gpid, traits: definition.traits.deep_dup)
  end

  after_update_commit :broadcast_changes

  scope :on_map, -> { where.not(game_map_id: nil) }
  scope :in_deck, ->(deck) { where(deck_id: deck).order(:deck_position) }
  scope :in_hand, ->(side) { where(hand_side: side) }

  def in_deck? = deck_id.present?
  def in_hand? = hand_side.present?
  def on_map? = game_map_id.present?

  # Last write wins; a dropped piece snaps to the grid of the layout board
  # under it (coordinates are map space; the grid is board-local) and comes to
  # the top of its map.
  def move_to!(x, y)
    x, y = snap(x, y)
    update!(x:, y:, z_order: next_z(game_map_id))
  end

  # Hand card → map (played face up). One update so the dispatcher fires once.
  def play_to!(game_map, x, y)
    return false unless in_hand?
    place_on_map!(game_map, x, y, reveal: true)
  end

  # Places the piece on a map from wherever it is (hand or deck): snaps to the
  # board grid and comes to the top. reveal clears the mask (face up); otherwise
  # the mask is forced obscured (face down to everyone) when the piece can be
  # masked. One update so the dispatcher fires once.
  def place_on_map!(game_map, x, y, reveal:, by: nil)
    relocate_to!(game_map, x, y, traits: reveal ? clear_mask(traits) : obscure_mask(traits, by))
  end

  # Moves the piece onto a map at a map-space point from wherever it is (deck,
  # hand or another map): snaps to the board grid under it, comes to the top,
  # and clears its non-map location. Mask state is preserved unless new traits
  # are passed in. Used by SendToLocation and card play.
  def relocate_to!(game_map, x, y, traits: self.traits)
    entry = game.board_layout(game_map).entry_at(x, y)
    board = entry&.board
    x, y = snap(x, y, game_map:)
    update!(hand_side: nil, deck_id: nil, deck_position: nil,
            game_map: game_map, board: board, x:, y:, z_order: next_z(game_map.id), traits:)
  end

  # Right-click menu commands the piece exposes (TriggerAction, SendToLocation
  # or CounterGlobalKeyCommand traits with menu text). Each is {label, key};
  # firing key through PieceCommand runs it.
  def menu_commands
    traits.filter_map do |trait|
      next unless %w[trigger send_to global_key].include?(trait["kind"])
      next if trait["command"].blank? || trait["key"].blank?
      { "label" => trait["command"], "key" => trait["key"] }
    end
  end

  # Menu commands currently available, dropping any a RestrictCommands trait
  # hides while its expression holds. global_props are the game's properties,
  # which restriction expressions may reference alongside the piece's own.
  def available_commands(global_props = {})
    commands = menu_commands
    return commands if commands.empty?

    restricted = restricted_command_keys(global_props)
    restricted.empty? ? commands : commands.reject { |c| restricted.include?(c["key"]) }
  end

  # The piece's VASSAL properties (BasicPiece name, markers, dynamic property
  # values) plus its current location — the namespace $property$ tokens in
  # command traits resolve against, alongside the game's global properties.
  def vassal_properties
    props = {}
    traits.each do |trait|
      case trait["kind"]
      when "basic"
        props["pieceName"] = props["BasicName"] = trait["name"].to_s if trait["name"].present?
        (trait["properties"] || {}).each { |k, v| props[k] = v.to_s }
      when "marker" then (trait["properties"] || {}).each { |k, v| props[k] = v.to_s }
      when "dynamic_property" then props[trait["name"]] = trait["value"].to_s
      end
    end
    props["LocationName"] = props["location"] = location_name.to_s
    props["newPieceName"] = props["oldPieceName"] = props["pieceName"]
    props.compact
  end

  # Map or hand card → on top of a deck's discard.
  def discard_to!(deck)
    top = game.game_pieces.in_deck(deck).minimum(:deck_position).to_i
    update!(deck: deck, deck_position: top - 1,
            hand_side: nil, game_map_id: nil, board_id: nil, x: nil, y: nil)
  end

  def layout_entry_at(x, y)
    game_map && game.board_layout(game_map).entry_at(x, y)
  end

  # Where the piece sits, in module terms ("1015", "Turn 3", a zone name...)
  def location_name
    layout_entry_at(x.to_i, y.to_i)&.location_name(x.to_i, y.to_i)
  end

  # Toggles the mask trait: obscured shows only the back image to everyone.
  def flip!(by:)
    update_trait("mask") do |trait|
      trait["obscured_by"] = trait["obscured_by"].present? ? nil : by
    end
  end

  # Steps the rotate trait one facing (or 15° for free rotators). The stored
  # angle uses VASSAL's convention (PiecesHelper#piece_rotation negates it).
  def rotate!(direction)
    update_trait("rotate") do |trait|
      step = trait["free"] ? 15.0 : 360.0 / trait["facings"].to_i.clamp(1, 360)
      trait["angle"] = (trait["angle"].to_f - step * direction) % 360
    end
  end

  # Steps a layer trait following VASSAL's value semantics: positive = active
  # at that 1-based level, negative = inactive. Layers with at most one
  # meaningful (non-blank) image are on/off markers: a step shows that image or
  # hides it, ignoring the delta. Multi-level always-active layers wrap; the
  # rest deactivate below level 1 and clamp at the top.
  def cycle_layer!(index, delta)
    update_trait("layer", index) do |trait|
      images = trait["images"] || []
      size = images.size
      return false if size.zero?

      meaningful = images.each_index.select { |i| images[i].to_s.strip.present? }
      value = trait["value"].to_i
      trait["value"] =
        if meaningful.size <= 1
          on_level = (meaningful.first || 0) + 1
          showing = value.positive? && images[value - 1].to_s.strip.present?
          showing ? -1 : on_level
        elsif trait["always_active"]
          level = value.positive? ? value : 1
          ((level - 1 + delta) % size) + 1
        else
          level = (value.positive? ? value : 0) + delta
          level < 1 ? -1 : level.clamp(1, size)
        end
    end
  end

  # Steps a numeric dynamic property (e.g. a hit counter) by delta, clamped to
  # its [min, max] range (wrapping if the property wraps).
  def adjust_property!(index, delta)
    update_trait("dynamic_property", index) do |trait|
      next unless trait["numeric"]
      min = trait["min"].to_i
      max = trait["max"].to_i
      value = trait["value"].to_i + delta
      value = if trait["wrap"] && max >= min
        min + (value - min) % (max - min + 1)
      else
        value.clamp(min, max)
      end
      trait["value"] = value.to_s
    end
  end

  private

  def snap(x, y, game_map: self.game_map)
    return [ x, y ] unless game_map
    entry = game.board_layout(game_map).entry_at(x, y) or return [ x, y ]
    local_x, local_y = entry.board.snap_point(x - entry.x, y - entry.y)
    [ local_x + entry.x, local_y + entry.y ]
  end

  def next_z(map_id)
    game.game_pieces.where(game_map_id: map_id).maximum(:z_order).to_i + 1
  end

  def clear_mask(source)
    updated = source.deep_dup
    mask = updated.find { |t| t["kind"] == "mask" }
    mask["obscured_by"] = nil if mask
    updated
  end

  # Forces the mask obscured (hidden to everyone). A piece with no mask trait
  # cannot be hidden, so it is returned unchanged (it shows its front).
  def obscure_mask(source, by)
    updated = source.deep_dup
    mask = updated.find { |t| t["kind"] == "mask" }
    mask["obscured_by"] = by if mask
    updated
  end

  # JSON columns aren't dirty-tracked on in-place mutation: always deep_dup,
  # modify the copy, reassign.
  def update_trait(kind, index = 0)
    updated = traits.deep_dup
    trait = updated.select { |t| t["kind"] == kind }[index]
    return false unless trait
    yield trait
    update!(traits: updated)
    true
  end

  # Keystrokes hidden by a RestrictCommands trait whose expression currently
  # matches. Properties are evaluated only if a restriction exists (the piece's
  # own plus the game's globals).
  def restricted_command_keys(global_props)
    restrictions = traits.select { |t| t["kind"] == "restrict_commands" }
    return [] if restrictions.empty?

    props = vassal_properties.merge(global_props)
    restrictions.flat_map do |trait|
      Vassal::PropertyExpression.match?(trait["property_match"], props) ? Array(trait["keys"]) : []
    end
  end

  def one_location_at_most
    places = [ deck_id, hand_side.presence, game_map_id ].compact
    errors.add(:base, "a piece can be in only one place") if places.size > 1
  end

  # State-aware broadcasting. In-deck pieces are silent (deck markers carry the
  # count); in-hand pieces replace only in their owner's side stream; on-map
  # pieces replace publicly. Transitions are handled by the controllers/Game
  # methods that emit the cross-stream append/remove explicitly.
  def broadcast_changes
    return if in_deck?

    if in_hand?
      broadcast_replace_to game, hand_side, target: ActionView::RecordIdentifier.dom_id(self, :hand),
        partial: "game_pieces/hand_card", locals: { game_piece: self, game_module: game.game_module }
    else
      broadcast_replace_to game,
        partial: "game_pieces/game_piece", locals: { game_piece: self, game_module: game.game_module }
    end
  end
end
