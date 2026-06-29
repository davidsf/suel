class Game < ApplicationRecord
  COPY_BATCH_SIZE = 500

  belongs_to :game_module
  belongs_to :scenario
  belongs_to :creator, class_name: "User"
  has_many :players, dependent: :destroy
  has_many :game_pieces, dependent: :destroy
  has_many :game_events, dependent: :destroy

  enum :status, %w[open finished].index_by(&:itself), default: "open"

  validates :name, presence: true
  validate :scenario_must_be_ready, on: :create

  delegate :sides, to: :game_module
  delegate :board_layout, to: :scenario

  def free_sides
    sides - players.pluck(:side)
  end

  def player_for(user)
    user && players.find_by(user: user)
  end

  # Copies the scenario's placed pieces as this game's mutable pieces.
  # Coordinates are copied verbatim: pieces sharing a point form a stack and
  # the table fans them out client-side, VASSAL style. Pieces sitting on a
  # player_hand map become hand cards of that side instead of map pieces
  # (otherwise a saved game would leak everyone's hand).
  def copy_scenario_pieces!
    now = Time.current
    hand_sides = game_module.game_maps.kind_player_hand.pluck(:id, :side).to_h
    rows = scenario.scenario_pieces.where.not(game_map_id: nil).order(:z_order).map do |piece|
      side = hand_sides[piece.game_map_id]
      {
        game_id: id,
        gpid: piece.gpid,
        name: piece.name,
        z_order: piece.z_order,
        type_string: piece.type_string,
        traits: piece.traits,
        hand_side: side,
        game_map_id: side ? nil : piece.game_map_id,
        board_id: side ? nil : piece.board_id,
        x: side ? nil : piece.x.to_i,
        y: side ? nil : piece.y.to_i,
        created_at: now, updated_at: now
      }
    end
    rows.each_slice(COPY_BATCH_SIZE) { |slice| GamePiece.insert_all(slice) }
  end

  # Materializes each deck's defined cards as live in-deck game pieces, with a
  # shuffled order unless the module marks the deck shuffle="Never".
  def materialize_decks!
    now = Time.current
    game_module.decks.includes(:piece_definitions).each do |deck|
      cards = deck.piece_definitions.to_a
      order = deck.settings["shuffle"] == "Never" ? cards : cards.shuffle
      rows = order.each_with_index.map do |card, position|
        {
          game_id: id, deck_id: deck.id, deck_position: position,
          gpid: card.gpid, name: card.name,
          type_string: card.type_string, traits: card.traits,
          z_order: 0, created_at: now, updated_at: now
        }
      end
      rows.each_slice(COPY_BATCH_SIZE) { |slice| GamePiece.insert_all(slice) }
    end
  end

  def deck_card_counts
    game_pieces.where.not(deck_id: nil).group(:deck_id).count
  end

  # Draws the top card of a deck into a side's hand. The single update! fires
  # the piece dispatcher (appends the card to the side stream); we broadcast
  # the public deck marker and the log event ourselves (no card identity).
  def draw_card!(deck, side:)
    card = nil
    transaction do
      card = game_pieces.in_deck(deck).lock.first or return nil
      card.update!(deck_id: nil, deck_position: nil, hand_side: side)
    end
    broadcast_deck_marker(deck)
    broadcast_hand_count(side)
    log!("#{side} roba 1 carta de #{deck.name}", kind: "deck")
    card
  end

  # Draws the top piece of a deck straight onto the table at (x, y), VASSAL
  # style (drag a piece out of the cup). Revealed face up when the DrawPile is
  # drawFaceUp. The deck→map transition is silent in the dispatcher (a replace
  # to a not-yet-rendered node), so we append the piece to the public map
  # container ourselves and refresh the deck marker.
  def draw_to_map!(deck, by:, game_map:, x:, y:)
    card = nil
    transaction do
      card = game_pieces.in_deck(deck).lock.first or return nil
      card.place_on_map!(game_map, x, y, reveal: deck.draw_face_up?, by:)
    end
    broadcast_deck_marker(deck)
    broadcast_append_to self, target: ActionView::RecordIdentifier.dom_id(game_map, :pieces),
      partial: "game_pieces/game_piece", locals: { game_piece: card, game_module: game_module }
    identity = deck.draw_face_up? ? card.name : "una ficha"
    log!("#{by} roba #{identity} de #{deck.name}", kind: "deck")
    card
  end

  def shuffle_deck!(deck, by:)
    reorder_deck!(deck)
    broadcast_deck_marker(deck)
    log!("#{by} baraja #{deck.name}", kind: "deck")
  end

  # Moves every card of the discard pile into its reshuffle target and shuffles.
  def reshuffle_deck!(deck, by:)
    target = deck_named(deck.settings["reshuffleTarget"]) or return false
    game_pieces.in_deck(deck).update_all(deck_id: target.id)
    reorder_deck!(target)
    broadcast_deck_marker(deck)
    broadcast_deck_marker(target)
    log!("#{by} rebaraja #{deck.name} en #{target.name}", kind: "deck")
    true
  end

  def deck_named(name)
    game_module.decks.detect { |d| d.name == name }
  end

  # Global properties read/written by the module's command traits
  # (SetGlobalProperty). Stored as strings, VASSAL-style.
  def property(name) = properties[name.to_s]

  def set_property!(name, value)
    update!(properties: properties.merge(name.to_s => value.to_s))
  end

  def deck_named_id(id)
    game_module.decks.detect { |d| d.id == id.to_i }
  end

  # After a card is played hand → map: the transition is silent in the
  # dispatcher (a replace to a not-yet-rendered node), so append it to the
  # public map container explicitly. The actor drops it from their tray.
  def after_card_played(card, by:)
    broadcast_append_to self, target: ActionView::RecordIdentifier.dom_id(card.game_map, :pieces),
      partial: "game_pieces/game_piece", locals: { game_piece: card, game_module: game_module }
    broadcast_remove_to self, by, target: ActionView::RecordIdentifier.dom_id(card, :hand)
    broadcast_hand_count(by)
    log!("#{by} juega #{card.name}", kind: "deck")
  end

  # After a card is discarded to a deck. From the map, remove the public piece
  # node (the dispatcher is silent once the card is in a deck). From a hand,
  # update the owner's count badge. The log hides the identity for face-down
  # destinations.
  def after_card_discarded(card, deck:, by:, from_hand:)
    if from_hand
      broadcast_remove_to self, by, target: ActionView::RecordIdentifier.dom_id(card, :hand)
      broadcast_hand_count(by)
    else
      broadcast_remove_to self, target: ActionView::RecordIdentifier.dom_id(card)
    end
    broadcast_deck_marker(deck)
    identity = deck.face_down? ? "una carta" : card.name
    log!("#{by} descarta #{identity} en #{deck.name}", kind: "deck")
  end

  # Broadcasts the side effects of a PieceCommand run. Pieces moved in place
  # already broadcast their own replace; here we insert pieces newly placed on a
  # map (their replace was a no-op for viewers), refresh decks that lost pieces,
  # and write each ReportState message to the log.
  def apply_command_result(cmd)
    cmd.placed.each do |piece|
      broadcast_append_to self, target: ActionView::RecordIdentifier.dom_id(piece.game_map, :pieces),
        partial: "game_pieces/game_piece", locals: { game_piece: piece, game_module: game_module }
    end
    cmd.source_decks.uniq.each { |deck| broadcast_deck_marker(deck) }
    cmd.reports.each { |message| log!(message, kind: "chat") }
  end

  def broadcast_deck_marker(deck)
    broadcast_replace_to self, target: ActionView::RecordIdentifier.dom_id(deck),
      partial: "decks/deck_marker", locals: { deck: deck, game: self }
  end

  def broadcast_hand_count(side)
    broadcast_replace_to self, target: "hand_count_#{side.parameterize}",
      partial: "games/hand_count", locals: { game: self, side: side }
  end

  def hand_card_count(side)
    game_pieces.in_hand(side).count
  end

  def top_card(deck)
    game_pieces.in_deck(deck).first
  end

  private

  def reorder_deck!(deck)
    ids = game_pieces.in_deck(deck).pluck(:id).shuffle
    ids.each_with_index { |id, position| game_pieces.where(id:).update_all(deck_position: position) }
  end

  def log!(body, kind:)
    game_events.create!(kind: kind, body: body)
  end

  def scenario_must_be_ready
    errors.add(:scenario, "no está listo") unless scenario&.ready?
  end
end
