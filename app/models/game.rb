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

  private

  def scenario_must_be_ready
    errors.add(:scenario, "no está listo") unless scenario&.ready?
  end
end
