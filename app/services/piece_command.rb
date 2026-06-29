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

  def initialize(game, by:)
    @game = game
    @by = by
    @touched = {}       # id => GamePiece, deduped and in first-touched order
    @reports = []       # resolved ReportState messages, in order
    @placed = []        # pieces moved onto a map from elsewhere (deck/hand)
    @source_decks = []  # decks those pieces came from, for marker refresh
    @removed = []       # pieces destroyed (Delete/Replace), for removal broadcast
  end

  # Fires keystroke at piece and returns the dispatcher (touched pieces +
  # reports). keystroke is a canonical NamedKeyStroke (see TraitRegistry).
  def self.run(piece, keystroke, by:)
    new(piece.game, by:).tap { |cmd| cmd.fire(piece, keystroke) }
  end

  def fire(piece, keystroke, depth = 0)
    return if depth > MAX_DEPTH || keystroke.blank?

    piece.traits.each do |trait|
      case trait["kind"]
      when "trigger"      then run_trigger(piece, trait, keystroke, depth)
      when "set_property" then run_set_property(piece, trait, keystroke)
      when "send_to"      then run_send_to(piece, trait, keystroke)
      when "global_key"   then run_global_key(trait, keystroke, depth)
      when "place_marker" then run_place_marker(piece, trait, keystroke)
      when "replace"      then run_replace(piece, trait, keystroke)
      when "delete"       then run_delete(piece, trait, keystroke)
      when "clone"        then run_clone(piece, trait, keystroke)
      when "report"       then run_report(piece, trait, keystroke)
      end
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

  # Pieces a CounterGlobalKeyCommand applies to. Only deck targeting is
  # supported so far (the top N of a named deck, or all of it).
  def targets(trait)
    return [] if trait["deck"].blank?

    deck = @game.deck_named(trait["deck"]) or return []
    scope = @game.game_pieces.in_deck(deck)
    count = trait["count"].to_i
    count.positive? ? scope.limit(count).to_a : scope.to_a
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
