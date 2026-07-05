# Runs a VASSAL key command against a piece by delivering a named keystroke to
# its trait stack, the way VASSAL propagates a KeyStroke through a Decorator
# chain. Traits react: a TriggerAction performs its action keystrokes (which are
# dispatched in turn), SetGlobalProperty writes a game property, SendToLocation
# moves the piece, a CounterGlobalKeyCommand relays a keystroke to pieces in a
# deck, and ReportState logs a message.
#
# Commands chain and cross pieces (reveal: a marker fires a global key at a
# hidden-units deck so a real unit sends itself to the marker's location, then
# the marker removes itself), so dispatch is recursive with a depth guard.
class PieceCommand
  MAX_DEPTH = 25

  attr_reader :touched, :reports, :placed, :source_decks, :removed

  def initialize(game, by:, deck_choice: nil)
    @game = game
    @by = by
    @deck_choice = deck_choice # player's pick for a prompting ReturnToDeck
    @touched = {}       # id => GamePiece, deduped and in first-touched order
    @reports = []       # resolved ReportState messages, in order
    @placed = []        # pieces moved onto a map from elsewhere (deck/hand)
    @source_decks = []  # decks pieces left or joined, for marker refresh
    @removed = []       # pieces destroyed or sent off-map, for removal broadcast
  end

  # Fires keystroke at piece and returns the dispatcher (touched pieces +
  # reports). keystroke is a canonical NamedKeyStroke (see TraitRegistry).
  def self.run(piece, keystroke, by:, deck_choice: nil)
    new(piece.game, by:, deck_choice:).tap { |cmd| cmd.fire(piece, keystroke) }
  end

  # Fires a module-level GlobalKeyCommand (a trait-shaped spec from
  # GameModule#global_key_commands) at every matching piece, the way
  # VASSAL.build.module.GlobalKeyCommand#apply searches all maps.
  def self.broadcast(game, spec, by:)
    new(game, by:).tap do |cmd|
      cmd.targets(spec).each { |piece| cmd.fire(piece, spec["global_key"]) }
      cmd.report(spec["report_format"])
    end
  end

  # Expands and logs a module-level report format (no piece context).
  def report(format)
    @reports << format.gsub(/\$([^$]+)\$/) { @game.property($1) || "" } if format.present?
  end

  def fire(piece, keystroke, depth = 0)
    return if depth > MAX_DEPTH || keystroke.blank?

    piece.traits.each do |trait|
      case trait["kind"]
      when "trigger"      then run_trigger(piece, trait, keystroke, depth)
      when "set_property" then run_set_property(piece, trait, keystroke)
      when "send_to"      then run_send_to(piece, trait, keystroke)
      when "return_to_deck" then run_return_to_deck(piece, trait, keystroke)
      when "global_key"   then run_global_key(trait, keystroke, depth)
      when "place_marker" then run_place_marker(piece, trait, keystroke)
      when "replace"      then run_replace(piece, trait, keystroke)
      when "delete"       then run_delete(piece, trait, keystroke)
      when "clone"        then run_clone(piece, trait, keystroke)
      when "report"       then run_report(piece, trait, keystroke)
      end
    end
  end

  # Pieces a Global Key Command applies to, per its GlobalCommandTarget: a
  # named deck (the top N or all of it), or the on-map pieces — optionally
  # narrowed to one map by a location fast-match, then by the property
  # fast-match and the BeanShell propertiesFilter. Divergences from VASSAL,
  # acceptable so far: hand/deck pieces are excluded from non-DECK targets
  # (VASSAL reaches deck pieces per deckCount), and a legacy deck trait
  # count of 0 still means "all".
  def targets(trait)
    target = Vassal::GlobalCommandTarget.parse(trait["target"])
    if target&.deck_target? || (target.nil? && trait["deck"].present?)
      deck = @game.deck_named(target&.deck.presence || trait["deck"]) or return []
      scope = @game.game_pieces.in_deck(deck)
      count = trait["count"].to_i
      count.positive? ? scope.limit(count).to_a : scope.to_a
    else
      scope = @game.game_pieces.on_map
      if target&.fast_match_location? && %w[MAP ZONE LOCATION XY].include?(target.target_type) && target.map.present?
        map = @game.game_module.game_maps.find_by(name: target.map)
        scope = map ? scope.where(game_map: map) : GamePiece.none
      end
      scope.select { |piece| matches?(piece, target, trait["property_filter"]) }
    end
  end

  private

  def run_trigger(piece, trait, keystroke, depth)
    return unless trait["key"] == keystroke || Array(trait["watch_keys"]).include?(keystroke)

    Array(trait["action_keys"]).each { |action| fire(piece, action, depth + 1) }
  end

  def run_set_property(piece, trait, keystroke)
    Array(trait["changes"]).each do |change|
      next unless change["key"] == keystroke

      current = @game.property(trait["name"]).to_s
      value =
        case change["op"]
        when "I" then (current.to_i + change["value"].to_i).to_s
        else resolve(change["value"], piece)
        end
      @game.set_property!(trait["name"], value)
    end
  end

  def run_send_to(piece, trait, keystroke)
    return unless trait["key"] == keystroke

    dest = destination(piece, trait) or return
    from_deck = piece.deck if piece.in_deck?
    arrived = !piece.on_map?
    piece.relocate_to!(*dest)
    touch(piece)
    if arrived
      @placed << piece
      @source_decks << from_deck if from_deck
    end
  end

  # ReturnToDeck: sends the piece back to a DrawPile — the trait's deck (a
  # $property$-capable name expression) or the player's pick when the trait
  # prompts for one (no pick = no-op, like cancelling VASSAL's dialog). The
  # piece leaves the map, so its public node is broadcast-removed and the
  # destination deck's marker refreshes.
  def run_return_to_deck(piece, trait, keystroke)
    return unless trait["key"] == keystroke

    deck = trait["select"] ? @deck_choice : @game.deck_named(resolve(trait["deck"], piece))
    return unless deck

    from_map = piece.on_map?
    piece.discard_to!(deck)
    touch(piece)
    @removed << piece if from_map
    @source_decks << deck
  end

  def run_global_key(trait, keystroke, depth)
    return unless trait["key"] == keystroke && trait["global_key"].present?

    targets(trait).each { |target| fire(target, trait["global_key"], depth + 1) }
  end

  # Stamps a marker counter onto the piece: instantiates the spec's palette
  # definition as a new on-map piece at the piece's location (plus offset),
  # tracked as placed so it is broadcast onto the map.
  def run_place_marker(piece, trait, keystroke)
    return unless trait["key"] == keystroke && piece.on_map?

    definition = @game.game_module.piece_definition_for_spec(trait["spec"]) or return
    place(definition, on: piece, offset: trait)
  end

  # Replace: place the replacement piece at the original's location, then remove
  # the original (PlaceMarker + Delete). "Change status to …" markers.
  def run_replace(piece, trait, keystroke)
    return unless trait["key"] == keystroke && piece.on_map?

    definition = @game.game_module.piece_definition_for_spec(trait["spec"]) or return
    place(definition, on: piece, offset: trait)
    remove(piece)
  end

  # Delete: destroy the piece. The trait loop keeps iterating the now-destroyed
  # in-memory record harmlessly; no later trait re-saves it.
  def run_delete(piece, trait, keystroke)
    return unless trait["key"] == keystroke

    remove(piece)
  end

  # Clone: duplicate the piece on top of itself. A GamePiece responds to the same
  # name/type_string/traits/gpid readers create_on_map! uses, so it is its own
  # "definition".
  def run_clone(piece, trait, keystroke)
    return unless trait["key"] == keystroke && piece.on_map?

    place(piece, on: piece, offset: nil)
  end

  # Instantiates a definition (palette slot or another piece) on top of the stack
  # at on's location plus an optional {x_off,y_off}; tracks it as placed.
  def place(definition, on:, offset:)
    piece = GamePiece.create_on_map!(
      game: @game, game_map: on.game_map, board: on.board,
      x: on.x.to_i + offset.to_h["x_off"].to_i, y: on.y.to_i + offset.to_h["y_off"].to_i,
      definition: definition, gpid: offset.to_h["gpid"] || definition.gpid
    )
    touch(piece)
    @placed << piece
  end

  def remove(piece)
    return if @removed.include?(piece)

    @touched.delete(piece.id)
    piece.destroy!
    @removed << piece
  end

  def run_report(piece, trait, keystroke)
    return unless Array(trait["keys"]).include?(keystroke) && trait["format"]

    @reports << resolve(trait["format"], piece)
  end

  # A target piece passes the property fast-match and then the BeanShell
  # propertiesFilter; properties resolve on the piece first, then the game's
  # globals, like getProperty.
  def matches?(piece, target, filter)
    props = @game.properties.to_h.merge(piece.vassal_properties)
    return false if target && !target.property_match?(props)
    filter.blank? || Vassal::PropertyExpression.match?(filter, props)
  end

  # Resolves a SendToLocation trait to [game_map, map_x, map_y], or nil. Grid
  # destinations (G/R/Z) resolve a $property$ location name through the board's
  # grid; L is a fixed board-local point. Coordinates are shifted by the board's
  # position in the layout to map space.
  def destination(piece, trait)
    game_map = @game.game_module.game_maps.find_by(name: trait["map"]) or return nil
    layout = @game.board_layout(game_map)
    entry = trait["board"].present? ? layout.entry_for(trait["board"]) : layout.entries.first
    board = entry&.board or return nil

    local =
      if trait["dest"] == "L"
        [ trait["x"].to_i, trait["y"].to_i ]
      else
        name = resolve(trait["grid_location"] || trait["region"] || trait["zone"], piece)
        board.point_for_location(name)
      end
    return nil unless local

    [ game_map, entry.x + local[0], entry.y + local[1] ]
  end

  # Expands $property$ tokens against the piece's properties then the game's
  # global properties; unknown tokens resolve to empty, VASSAL-style.
  def resolve(expression, piece)
    props = piece.vassal_properties
    expression.to_s.gsub(/\$([^$]+)\$/) { props[$1] || @game.property($1) || "" }
  end

  def touch(piece)
    @touched[piece.id] = piece
  end
end
