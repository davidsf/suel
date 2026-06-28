class GamePiece < ApplicationRecord
  belongs_to :game
  belongs_to :game_map, optional: true
  belongs_to :board, optional: true
  belongs_to :deck, optional: true

  # A piece is in exactly one place: in a deck, in a player's hand, or on a map.
  validate :one_location_at_most

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
    entry = game.board_layout(game_map).entry_at(x, y)
    board = entry&.board
    x, y = snap(x, y, game_map:)
    updated = clear_mask(traits)
    update!(hand_side: nil, deck_id: nil, deck_position: nil,
            game_map: game_map, board: board, x:, y:,
            z_order: next_z(game_map.id), traits: updated)
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
